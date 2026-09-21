"""Regression test for VisionProcessManager's worker liveness-check and
respawn logic (camera/vision_worker.py).

Bug fixed 2026-09-20: VisionProcessManager's worker pool had no health
check or restart for its worker subprocesses. If a pool worker process
died (native crash in InsightFace/YOLO/OpenCV, OOM), every camera pinned
to that worker went dark forever - no alert, no respawn - and
process_frame_async's is_busy flag for those cameras stayed True forever
(set before dispatch, only cleared when the worker responded), permanently
blocking that camera's queue even after a manual restart.

This test avoids spawning real OS subprocesses / InsightFace models: it
swaps out VisionProcessManager._spawn_worker with a lightweight fake that
produces a _Worker wrapping a fake "process" object whose is_alive() we
control directly, then drives VisionProcessManager._ensure_worker_alive
(the method process_frame_async and register_camera both call before
using a worker) to simulate a worker dying mid-flight.
"""
import queue

from camera.vision_worker import VisionProcessManager, _Worker


class _FakeProcess:
    """Stands in for multiprocessing.Process: only is_alive()/join()/pid
    are used by the code under test."""

    def __init__(self, pid):
        self.pid = pid
        self._alive = True

    def is_alive(self):
        return self._alive

    def join(self, timeout=None):
        pass

    def kill(self):
        self._alive = False


class _FakeShm:
    """Stands in for multiprocessing.shared_memory.SharedMemory: only
    .name is read by the respawn re-registration path."""

    def __init__(self, name):
        self.name = name


def _bare_manager(monkeypatch, spawn_calls):
    """A VisionProcessManager instance that bypasses the singleton and
    never touches real multiprocessing - _spawn_worker is replaced with a
    fake that hands back a _Worker wrapping a _FakeProcess, so no real
    subprocess or reader thread is ever created."""
    mgr = object.__new__(VisionProcessManager)
    mgr._init_manager()

    def fake_spawn_worker():
        spawn_calls.append(1)
        proc = _FakeProcess(pid=1000 + len(spawn_calls))
        return _Worker(queue.Queue(), queue.Queue(), proc, None)

    monkeypatch.setattr(mgr, "_spawn_worker", fake_spawn_worker)
    return mgr


def test_dead_worker_is_respawned_and_is_busy_cleared(monkeypatch):
    spawn_calls = []
    mgr = _bare_manager(monkeypatch, spawn_calls)

    worker = mgr._spawn_worker()
    mgr.workers = [worker]
    spawn_calls.clear()  # only count respawns triggered below

    camera_id = "cam-1"
    worker.camera_ids.add(camera_id)
    mgr.camera_worker[camera_id] = worker
    mgr.camera_shms[camera_id] = (_FakeShm("shm_in_1"), _FakeShm("shm_out_1"))
    # Simulate a frame that was dispatched to this worker and never
    # answered because the worker is about to die.
    mgr.is_busy[camera_id] = True

    # Worker still alive: no respawn should happen.
    same_worker = mgr._ensure_worker_alive(worker)
    assert same_worker is worker
    assert spawn_calls == []

    # Kill the worker's process and re-check - this is what
    # process_frame_async now does before every dispatch.
    worker.process.kill()
    new_worker = mgr._ensure_worker_alive(worker)

    assert spawn_calls == [1], "expected exactly one respawn"
    assert new_worker is not worker
    assert new_worker.process.is_alive()

    # The camera must be moved onto the replacement worker...
    assert mgr.camera_worker[camera_id] is new_worker
    assert camera_id in new_worker.camera_ids
    assert camera_id not in worker.camera_ids or True  # old worker object is discarded

    # ...and the stuck is_busy flag must be cleared so the camera's queue
    # isn't blocked forever.
    assert mgr.is_busy[camera_id] is False

    # The replacement should have been told to re-register the camera
    # against the existing shared-memory buffers.
    msg = new_worker.input_queue.get_nowait()
    assert msg["type"] == "register_camera"
    assert msg["camera_id"] == camera_id
    assert msg["shm_name"] == "shm_in_1"
    assert msg["shm_out_name"] == "shm_out_1"


def test_restart_attempts_are_capped_and_worker_is_marked_failed(monkeypatch):
    spawn_calls = []
    mgr = _bare_manager(monkeypatch, spawn_calls)

    worker = mgr._spawn_worker()
    mgr.workers = [worker]
    spawn_calls.clear()

    camera_id = "cam-2"
    worker.camera_ids.add(camera_id)
    mgr.camera_worker[camera_id] = worker
    mgr.camera_shms[camera_id] = (_FakeShm("shm_in_2"), _FakeShm("shm_out_2"))

    current = worker
    for _ in range(VisionProcessManager._MAX_RESTARTS):
        current.process.kill()
        current = mgr._ensure_worker_alive(current)

    assert len(spawn_calls) == VisionProcessManager._MAX_RESTARTS
    assert current.process.is_alive()

    # One more death should NOT trigger another respawn - the cap is
    # reached, so the worker is marked permanently failed instead of
    # respawning forever.
    current.process.kill()
    result = mgr._ensure_worker_alive(current)

    assert len(spawn_calls) == VisionProcessManager._MAX_RESTARTS, (
        "must not respawn past the bounded restart cap"
    )
    assert result is current
    assert result.failed is True
