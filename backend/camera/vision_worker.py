import multiprocessing as mp
from multiprocessing import shared_memory
import os
import threading
import time
import numpy as np
import traceback
import queue

def _vision_worker_process(input_queue, output_queue, max_h, max_w, dtype):
    """
    Dedicated process for running heavy AI inference.
    Initializes its own VisionService so models are loaded only once in this process.
    One or more of these processes run concurrently (see VisionProcessManager's
    worker pool) so cameras assigned to different processes get genuinely
    parallel inference instead of queueing behind each other.
    """
    print("[VisionWorkerProcess] Initializing AI Models in separate process...")

    shm_dict = {} # camera_id -> SharedMemory
    vision_services = {} # camera_id -> VisionServiceZones
    global_staff_list = []
    global_zones = []

    while True:
        try:
            req = input_queue.get()
            if req is None:
                break # Shutdown signal

            if req["type"] == "warmup":
                # Force the lazy InsightFace/YOLO singletons to load now,
                # ahead of any camera actually being viewed. This is the
                # ~30-60s cold-start cost (ONNX/torch imports + model
                # weight loading) that otherwise only pays off on the
                # first frame of the first camera someone opens - moving
                # it here lets it happen in the background right after
                # login instead of blocking the first camera view.
                try:
                    from camera.model_manager import ModelManager

                    mgr = ModelManager()
                    mgr.get_face_analysis()
                    mgr.get_yolo_detector("warmup")
                    output_queue.put({"type": "warmed_up"})
                except Exception as e:
                    output_queue.put({"type": "error", "error": f"Warmup failed: {e}"})
                continue

            if req["type"] == "update_staff":
                global_staff_list = req["staff_list"]
                for vs in vision_services.values():
                    vs.update_staff_embeddings(global_staff_list)
                output_queue.put({"type": "staff_updated"})
                continue

            if req["type"] == "update_zones":
                global_zones = req["zones"]
                for vs in vision_services.values():
                    vs.update_zone_polygons(global_zones)
                continue

            if req["type"] == "register_camera":
                cam_id = req["camera_id"]
                try:
                    shm_in = shared_memory.SharedMemory(name=req["shm_name"])
                    shm_out = shared_memory.SharedMemory(name=req["shm_out_name"])
                    shm_dict[cam_id] = (shm_in, shm_out)

                    from camera.vision_service_zones import VisionServiceZones
                    vs = VisionServiceZones(camera_name=str(cam_id))
                    if global_staff_list:
                        vs.update_staff_embeddings(global_staff_list)
                    if global_zones:
                        vs.update_zone_polygons(global_zones)
                    vision_services[cam_id] = vs

                    output_queue.put({"type": "camera_registered", "camera_id": cam_id})
                except Exception as e:
                    output_queue.put({"type": "error", "error": f"Failed to attach SHM for {cam_id}: {e}"})
                continue

            if req["type"] == "unregister_camera":
                cam_id = req["camera_id"]
                if cam_id in shm_dict:
                    shm_in, shm_out = shm_dict[cam_id]
                    shm_in.close()
                    shm_out.close()
                    try:
                        shm_in.unlink()
                        shm_out.unlink()
                    except FileNotFoundError:
                        pass
                    del shm_dict[cam_id]
                if cam_id in vision_services:
                    del vision_services[cam_id]
                continue

            if req["type"] == "process_frame":
                cam_id = req["camera_id"]
                frame_id = req["frame_id"]
                h = req["h"]
                w = req["w"]

                if cam_id not in shm_dict or cam_id not in vision_services:
                    continue

                shm_in, _ = shm_dict[cam_id]
                shared_in = np.ndarray((max_h, max_w, 3), dtype=dtype, buffer=shm_in.buf)

                # Copy the latest input frame for inference. The camera worker
                # draws smoothed overlays on the live frame, so we do not need
                # to copy an annotated frame back through shared memory.
                frame = np.copy(shared_in[:h, :w, :])
                _, face_events, equipment_events, incident_events, ppe_events = vision_services[cam_id].process_frame(frame, camera_id=cam_id)

                output_queue.put({
                    "type": "results",
                    "camera_id": cam_id,
                    "frame_id": frame_id,
                    "face_events": face_events,
                    "equipment_events": equipment_events,
                    "incident_events": incident_events,
                    "ppe_events": ppe_events
                })
        except Exception as e:
            traceback.print_exc()
            error_payload = {"type": "error", "error": str(e)}
            if isinstance(locals().get("req"), dict) and "camera_id" in req:
                error_payload["camera_id"] = req["camera_id"]
            output_queue.put(error_payload)

    # Cleanup
    for shm_in, shm_out in shm_dict.values():
        shm_in.close()
        shm_out.close()
        try:
            shm_in.unlink()
            shm_out.unlink()
        except FileNotFoundError:
            pass


def _default_pool_size() -> int:
    """
    Number of parallel inference subprocesses to run. CPU-only deployments
    benefit most (multiple cameras were previously serialized on one
    process); GPU deployments default to a single worker since a single
    stream already saturates the accelerator and extra processes would
    just contend for the same VRAM/context.
    """
    override = os.environ.get("VISION_WORKER_POOL_SIZE")
    if override:
        try:
            return max(1, int(override))
        except ValueError:
            pass

    try:
        from camera.constants.vision_constants import get_runtime_vision_config

        backend = get_runtime_vision_config()["backend"]
    except Exception:
        backend = "cpu"

    return 2 if backend == "cpu" else 1


class _Worker:
    __slots__ = (
        "input_queue",
        "output_queue",
        "process",
        "reader_thread",
        "camera_ids",
        "restart_count",
        "restart_window_start",
        "failed",
    )

    def __init__(self, input_queue, output_queue, process, reader_thread):
        self.input_queue = input_queue
        self.output_queue = output_queue
        self.process = process
        self.reader_thread = reader_thread
        self.camera_ids = set()
        # Restart bookkeeping for the health-check/respawn logic in
        # VisionProcessManager - bounded so a worker that keeps crashing
        # (e.g. a poison-pill frame, a broken model file) doesn't cause an
        # unbounded respawn loop.
        self.restart_count = 0
        self.restart_window_start = time.time()
        self.failed = False


class VisionProcessManager:
    """
    Public API is unchanged from the single-process version: start_process,
    update_staff, update_zones, register_camera, unregister_camera,
    process_frame_async, pop_result. Internally this now fans work out across
    a small pool of worker subprocesses so cameras don't serialize behind
    one another.
    """
    _instance = None
    _thread_lock = threading.Lock()

    # Bounded restart policy for dead pool workers: at most _MAX_RESTARTS
    # respawns within a rolling _RESTART_WINDOW_SEC window. If a worker
    # keeps dying faster than that, it's marked permanently failed and we
    # stop trying to respawn it (its cameras stay assigned to it and will
    # simply fail to get results, rather than us respawning forever).
    _MAX_RESTARTS = 5
    _RESTART_WINDOW_SEC = 300

    def __new__(cls, *args, **kwargs):
        with cls._thread_lock:
            if cls._instance is None:
                cls._instance = super(VisionProcessManager, cls).__new__(cls)
                cls._instance._init_manager(*args, **kwargs)
            return cls._instance

    def _init_manager(self, max_h=1080, max_w=1920, dtype=np.uint8):
        self.max_h = max_h
        self.max_w = max_w
        self.dtype = dtype

        self.pool_size = _default_pool_size()
        self.workers: list[_Worker] = []
        self.camera_shms = {}
        self.camera_worker = {}  # camera_id -> _Worker
        self.latest_results = {} # camera_id -> dict of events
        self.result_lock = threading.Lock()
        self.is_busy = {}

    def start_process(self):
        if self.workers:
            return

        for _ in range(self.pool_size):
            self.workers.append(self._spawn_worker())

        print(
            f"[VisionProcessManager] Started {len(self.workers)} inference worker process(es)."
        )

    def _spawn_worker(self) -> "_Worker":
        """
        Create one pool worker: fresh IPC queues, a fresh subprocess running
        _vision_worker_process, and a fresh reader thread draining its
        output_queue. Used both for initial pool creation (start_process)
        and to respawn a replacement when a worker is found dead
        (_ensure_worker_alive).
        """
        ctx = mp.get_context('spawn')
        input_queue = ctx.Queue(maxsize=4)
        output_queue = ctx.Queue()
        process = ctx.Process(
            target=_vision_worker_process,
            args=(input_queue, output_queue, self.max_h, self.max_w, self.dtype),
            daemon=True,
        )
        process.start()

        worker = _Worker(input_queue, output_queue, process, None)
        reader_thread = threading.Thread(
            target=self._read_results, args=(worker,), daemon=True
        )
        worker.reader_thread = reader_thread
        reader_thread.start()
        return worker

    def _ensure_worker_alive(self, worker: "_Worker") -> "_Worker":
        """
        Liveness check + bounded respawn for one pool worker. Called right
        before a worker is used (camera assignment or frame dispatch) so a
        crashed subprocess (native crash in InsightFace/YOLO/OpenCV, OOM)
        doesn't silently leave its cameras dark forever.

        If `worker` is dead, this respawns a replacement in place inside
        self.workers, reassigns every camera that was pinned to the dead
        worker to the replacement (re-issuing "register_camera" so the new
        process attaches the existing shared-memory buffers), and clears
        is_busy for those cameras so any frame that was in flight to the
        dead worker is dropped (fail-fast) rather than blocking the
        camera's queue forever. Returns the worker to actually use (either
        the same live worker, or its replacement).
        """
        if worker.process is not None and worker.process.is_alive():
            return worker

        if worker.failed:
            # Already gave up on this slot within the current restart
            # window - avoid respawning it again on every single dispatch.
            return worker

        now = time.time()
        if now - worker.restart_window_start > self._RESTART_WINDOW_SEC:
            worker.restart_window_start = now
            worker.restart_count = 0

        if worker.restart_count >= self._MAX_RESTARTS:
            worker.failed = True
            print(
                f"[VisionProcessManager] Worker (pid={worker.process.pid if worker.process else '?'}) "
                f"has died {worker.restart_count} times within {self._RESTART_WINDOW_SEC}s; "
                f"giving up on respawning it. Cameras stuck on this worker: {sorted(worker.camera_ids)}"
            )
            return worker

        worker.restart_count += 1
        print(
            f"[VisionProcessManager] Worker process (pid={worker.process.pid if worker.process else '?'}) "
            f"is dead. Respawning replacement (attempt {worker.restart_count}/{self._MAX_RESTARTS})..."
        )
        try:
            worker.process.join(timeout=0.1)
        except Exception:
            pass

        new_worker = self._spawn_worker()
        new_worker.restart_count = worker.restart_count
        new_worker.restart_window_start = worker.restart_window_start

        try:
            idx = self.workers.index(worker)
            self.workers[idx] = new_worker
        except ValueError:
            self.workers.append(new_worker)

        stale_camera_ids = list(worker.camera_ids)
        for cam_id in stale_camera_ids:
            new_worker.camera_ids.add(cam_id)
            self.camera_worker[cam_id] = new_worker

            # Unstick this camera's queue: whatever frame (if any) was in
            # flight to the dead worker is lost, fail fast instead of
            # leaving is_busy stuck True forever.
            self.is_busy[cam_id] = False
            with self.result_lock:
                self.latest_results.pop(cam_id, None)

            # Re-register the camera against the new process so it
            # reattaches the existing shared-memory buffers.
            if cam_id in self.camera_shms:
                shm_in, shm_out = self.camera_shms[cam_id]
                try:
                    new_worker.input_queue.put({
                        "type": "register_camera",
                        "camera_id": cam_id,
                        "shm_name": shm_in.name,
                        "shm_out_name": shm_out.name,
                    })
                except Exception:
                    pass

        return new_worker

    def _read_results(self, worker: "_Worker"):
        while True:
            try:
                res = worker.output_queue.get()
                if res.get("type") == "results":
                    cam_id = res["camera_id"]
                    with self.result_lock:
                        self.latest_results[cam_id] = res
                elif res.get("type") == "error" and res.get("camera_id"):
                    cam_id = res["camera_id"]
                    with self.result_lock:
                        self.latest_results[cam_id] = res
            except Exception:
                pass

    def _least_loaded_worker(self) -> "_Worker":
        candidates = [w for w in self.workers if not w.failed] or self.workers
        return min(candidates, key=lambda w: len(w.camera_ids))

    def update_staff(self, staff_list: list):
        for worker in self.workers:
            if worker.process and worker.process.is_alive():
                worker.input_queue.put({"type": "update_staff", "staff_list": staff_list})

    def warmup(self):
        """
        Pre-load the InsightFace/YOLO models in every pool worker process
        without registering any camera - lets the ~30-60s cold-start cost
        happen right after login (or whenever the caller decides), instead
        of blocking whichever camera the user opens first. Starts the
        process pool first if it isn't already running. Fire-and-forget:
        callers should not block waiting for the "warmed_up" response.
        """
        self.start_process()
        for worker in self.workers:
            if worker.process and worker.process.is_alive():
                try:
                    worker.input_queue.put_nowait({"type": "warmup"})
                except queue.Full:
                    pass

    def update_zones(self, zones: list):
        for worker in self.workers:
            if worker.process and worker.process.is_alive():
                try:
                    worker.input_queue.put_nowait({"type": "update_zones", "zones": zones})
                except queue.Full:
                    pass

    def register_camera(self, camera_id: str):
        if camera_id in self.camera_shms or not self.workers:
            return
        dummy = np.zeros((self.max_h, self.max_w, 3), dtype=self.dtype)
        shm_in = shared_memory.SharedMemory(create=True, size=dummy.nbytes)
        shm_out = shared_memory.SharedMemory(create=True, size=dummy.nbytes)
        self.camera_shms[camera_id] = (shm_in, shm_out)

        worker = self._least_loaded_worker()
        worker = self._ensure_worker_alive(worker)
        worker.camera_ids.add(camera_id)
        self.camera_worker[camera_id] = worker
        worker.input_queue.put({"type": "register_camera", "camera_id": camera_id, "shm_name": shm_in.name, "shm_out_name": shm_out.name})

    def unregister_camera(self, camera_id):
        worker = self.camera_worker.pop(camera_id, None)
        if worker is not None:
            worker.camera_ids.discard(camera_id)
            worker.input_queue.put({"type": "unregister_camera", "camera_id": camera_id})
        if camera_id in self.camera_shms:
            shm_in, shm_out = self.camera_shms.pop(camera_id)
            shm_in.close()
            shm_out.close()
            try:
                shm_in.unlink()
                shm_out.unlink()
            except FileNotFoundError:
                pass
        with self.result_lock:
            self.latest_results.pop(camera_id, None)
        self.is_busy.pop(camera_id, None)

    def process_frame_async(self, camera_id, frame, frame_id):
        if camera_id not in self.camera_shms:
            return False

        worker = self.camera_worker.get(camera_id)
        if worker is None:
            return False

        # Health-check before every dispatch: if this camera's worker
        # process died (native crash / OOM), respawn a replacement and
        # clear the stuck is_busy flag before deciding whether to send
        # this frame, instead of blocking the camera's queue forever.
        worker = self._ensure_worker_alive(worker)
        self.camera_worker[camera_id] = worker

        if self.is_busy.get(camera_id, False):
            return False

        h, w = frame.shape[:2]
        if h > self.max_h or w > self.max_w:
            return False

        shm_in, _ = self.camera_shms[camera_id]
        shared_array = np.ndarray((self.max_h, self.max_w, 3), dtype=self.dtype, buffer=shm_in.buf)
        shared_array[:h, :w, :] = frame

        self.is_busy[camera_id] = True
        try:
            worker.input_queue.put_nowait({"type": "process_frame", "camera_id": camera_id, "frame_id": frame_id, "h": h, "w": w})
        except queue.Full:
            self.is_busy[camera_id] = False
            return False
        return True

    def pop_result(self, camera_id):
        with self.result_lock:
            res = self.latest_results.pop(camera_id, None)
            if res:
                self.is_busy[camera_id] = False
            return res

vision_process_manager = VisionProcessManager()
