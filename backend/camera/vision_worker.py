import multiprocessing as mp
from multiprocessing import shared_memory
import threading
import numpy as np
import traceback
import queue

def _vision_worker_process(input_queue, output_queue, max_h, max_w, dtype):
    """
    Dedicated process for running heavy AI inference.
    Initializes its own VisionService so models are loaded only once in this process.
    """
    print("[VisionWorkerProcess] Initializing AI Models in separate process...")
    try:
        from camera.vision_service_zones import VisionServiceZones
        vision_service = VisionServiceZones()
    except Exception as e:
        print(f"[VisionWorkerProcess] Failed to initialize VisionService: {e}")
        output_queue.put({"type": "fatal", "error": str(e)})
        return
        
    shm_dict = {} # camera_id -> SharedMemory
    
    while True:
        try:
            req = input_queue.get()
            if req is None:
                break # Shutdown signal
            
            if req["type"] == "update_staff":
                vision_service.update_staff_embeddings(req["staff_list"])
                output_queue.put({"type": "staff_updated"})
                continue
                
            if req["type"] == "update_zones":
                vision_service.update_zone_polygons(req["zones"])
                continue
                
            if req["type"] == "register_camera":
                cam_id = req["camera_id"]
                try:
                    shm_in = shared_memory.SharedMemory(name=req["shm_name"])
                    shm_out = shared_memory.SharedMemory(name=req["shm_out_name"])
                    shm_dict[cam_id] = (shm_in, shm_out)
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
                continue

            if req["type"] == "process_frame":
                cam_id = req["camera_id"]
                frame_id = req["frame_id"]
                h = req["h"]
                w = req["w"]
                
                if cam_id not in shm_dict:
                    continue
                    
                shm_in, _ = shm_dict[cam_id]
                shared_in = np.ndarray((max_h, max_w, 3), dtype=dtype, buffer=shm_in.buf)
                
                # Copy the latest input frame for inference. The camera worker
                # draws smoothed overlays on the live frame, so we do not need
                # to copy an annotated frame back through shared memory.
                frame = np.copy(shared_in[:h, :w, :])
                _, face_events, equipment_events, incident_events, ppe_events = vision_service.process_frame(frame, camera_id=cam_id)
                
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

class VisionProcessManager:
    _instance = None
    _thread_lock = threading.Lock()
    
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
        
        self.input_queue = None
        self.output_queue = None
        self.process = None
        self.camera_shms = {}
        self.latest_results = {} # camera_id -> dict of events
        self.result_lock = threading.Lock()
        
    def start_process(self):
        if self.process is not None:
            return
            
        ctx = mp.get_context('spawn')
        self.input_queue = ctx.Queue(maxsize=4)
        self.output_queue = ctx.Queue()
        
        self.process = ctx.Process(
            target=_vision_worker_process,
            args=(self.input_queue, self.output_queue, self.max_h, self.max_w, self.dtype),
            daemon=True
        )
        self.process.start()
        
        # Start a thread to read results from the output queue continuously
        self.reader_thread = threading.Thread(target=self._read_results, daemon=True)
        self.reader_thread.start()
        
    def _read_results(self):
        while True:
            try:
                res = self.output_queue.get()
                if res.get("type") == "results":
                    cam_id = res["camera_id"]
                    with self.result_lock:
                        self.latest_results[cam_id] = res
                elif res.get("type") == "error" and res.get("camera_id"):
                    cam_id = res["camera_id"]
                    with self.result_lock:
                        self.latest_results[cam_id] = res
            except Exception as e:
                pass

    def update_staff(self, staff_list: list):
        if self.process and self.process.is_alive():
            self.input_queue.put({"type": "update_staff", "staff_list": staff_list})

    def update_zones(self, zones: list):
        if self.process and self.process.is_alive():
            try:
                self.input_queue.put_nowait({"type": "update_zones", "zones": zones})
            except queue.Full:
                pass

    def register_camera(self, camera_id: str):
        if camera_id in self.camera_shms or not self.input_queue:
            return
        dummy = np.zeros((self.max_h, self.max_w, 3), dtype=self.dtype)
        shm_in = shared_memory.SharedMemory(create=True, size=dummy.nbytes)
        shm_out = shared_memory.SharedMemory(create=True, size=dummy.nbytes)
        self.camera_shms[camera_id] = (shm_in, shm_out)
        self.input_queue.put({"type": "register_camera", "camera_id": camera_id, "shm_name": shm_in.name, "shm_out_name": shm_out.name})

    def unregister_camera(self, camera_id):
        if camera_id in self.camera_shms and self.input_queue:
            self.input_queue.put({"type": "unregister_camera", "camera_id": camera_id})
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
        if hasattr(self, 'is_busy') and camera_id in self.is_busy:
            del self.is_busy[camera_id]

    def process_frame_async(self, camera_id, frame, frame_id):
        if camera_id not in self.camera_shms:
            return False
            
        if not hasattr(self, 'is_busy'):
            self.is_busy = {}
            
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
            self.input_queue.put_nowait({"type": "process_frame", "camera_id": camera_id, "frame_id": frame_id, "h": h, "w": w})
        except queue.Full:
            self.is_busy[camera_id] = False
            return False
        return True

    def pop_result(self, camera_id):
        with self.result_lock:
            res = self.latest_results.pop(camera_id, None)
            if res and hasattr(self, 'is_busy'):
                self.is_busy[camera_id] = False
            return res
        return None

vision_process_manager = VisionProcessManager()
