import asyncio
import datetime
import os
import shutil
import threading
import time
import cv2
import numpy as np
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, WebSocket, WebSocketDisconnect
from fastapi.responses import Response
from sqlalchemy.orm import Session
from typing import List, Optional, Set
from urllib.parse import unquote
from pydantic import BaseModel, ConfigDict

from database import get_db, SessionLocal
import models
from camera.vision_service import vision_service
from events import event_engine

# ── Attendance session constants ──────────────────────────────────────────────
SESSION_GAP_SEC    = 5 * 3600   # 5 hours of absence → new session / new entry
LAST_SEEN_FREQ_SEC = 30         # update last_seen at most every 30 seconds

# Per-person in-memory timestamps (avoids hitting DB on every frame)
_last_db_write: dict   = {}   # {name: datetime} — when we last wrote to DB
_last_db_write_lock = threading.Lock()


def _maybe_mark_attendance(
    name: str, score: float,
    camera_id: Optional[int] = None,
    camera_name: Optional[str] = None,
    **kwargs
):
    """
    Session-aware attendance marking:

    1. If last DB write for this person was < LAST_SEEN_FREQ_SEC ago → skip (throttle).
    2. Look up the most recent Attendance record for this person (any date).
    3. If NO record exists OR last_seen > SESSION_GAP_SEC ago
           → create a NEW session record (entry_time = now).
    4. Otherwise
           → update last_seen on the existing open session.
       (exit_time is set manually via the checkout API, never here.)
    """
    if name == "Unknown":
        now = datetime.datetime.now(tz=datetime.timezone.utc)
        throttle_key = f"unknown_{camera_id}"
        with _last_db_write_lock:
            last_write = _last_db_write.get(throttle_key)
            if last_write and (now - last_write).total_seconds() < LAST_SEEN_FREQ_SEC:
                return
            _last_db_write[throttle_key] = now
            
        event_engine.publish_event(
            event_type="UnknownFaceDetected",
            camera_id=camera_id,
            camera_name=camera_name,
            confidence=score,
            details={"status": "detected"}
        )
        return

    now = datetime.datetime.now(tz=datetime.timezone.utc)

    # In-memory throttle — skip DB entirely if we wrote recently
    with _last_db_write_lock:
        last_write = _last_db_write.get(name)
        if last_write and (now - last_write).total_seconds() < LAST_SEEN_FREQ_SEC:
            return
        _last_db_write[name] = now

    db = SessionLocal()
    try:
        # Find most recent attendance record for this person
        latest: Optional[models.Attendance] = (
            db.query(models.Attendance)
            .filter(models.Attendance.staff_name == name)
            .order_by(models.Attendance.last_seen.desc())
            .first()
        )

        gap = (
            (now - latest.last_seen.replace(tzinfo=datetime.timezone.utc)).total_seconds()
            if latest and latest.last_seen
            else SESSION_GAP_SEC + 1   # treat as no record
        )

        if gap > SESSION_GAP_SEC:
            # ── New session ────────────────────────────────────────────────
            staff = db.query(models.Staff).filter(models.Staff.name == name).first()
            record = models.Attendance(
                staff_id    = staff.id if staff else None,
                staff_name  = name,
                confidence  = score,
                date        = now.date(),
                entry_time  = now,
                last_seen   = now,
                exit_time   = None,
                camera_id   = camera_id,
                camera_name = camera_name,
            )
            db.add(record)
            db.commit()
            cam_label = f"  @ {camera_name}" if camera_name else ""
            print(f"[Attendance] ✅ New session — {name}  ({score:.0%}){cam_label}  entry: {now.strftime('%H:%M')}")
            
            # Emit attendance event
            event_engine.publish_event(
                event_type="Attendance",
                camera_id=camera_id,
                camera_name=camera_name,
                confidence=score,
                details={"staff_name": name, "status": "check_in", "has_mask": kwargs.get("has_mask", True)}
            )
        else:
            # ── Update last_seen on open session ───────────────────────────
            if latest.camera_id != camera_id:
                event_engine.publish_event(
                    event_type="AreaTransition",
                    camera_id=camera_id,
                    camera_name=camera_name,
                    confidence=score,
                    details={"staff_name": name, "from_camera": latest.camera_name, "to_camera": camera_name}
                )
                latest.camera_id = camera_id
                latest.camera_name = camera_name

            latest.last_seen = now
            db.commit()
            # (silent — don't spam the log every 30 seconds)

    except Exception as e:
        print(f"[Attendance] Error for {name}: {e}")
        db.rollback()
    finally:
        db.close()


def _maybe_track_equipment(
    equip_class: str, track_id: int, score: float,
    camera_id: Optional[int] = None,
    camera_name: Optional[str] = None,
):
    """
    Log equipment detection.
    Update its location if it moved.
    """
    db = SessionLocal()
    try:
        now = datetime.datetime.now(tz=datetime.timezone.utc)
        equip_id_str = f"{equip_class} #{track_id}"
        
        # Ensure type exists
        eq_type = db.query(models.EquipmentType).filter(models.EquipmentType.name == equip_class).first()
        if not eq_type:
            eq_type = models.EquipmentType(name=equip_class)
            db.add(eq_type)
            db.commit()
            db.refresh(eq_type)
            
        # Ensure item exists
        item = db.query(models.EquipmentItem).filter(models.EquipmentItem.equipment_id == equip_id_str).first()
        if not item:
            item = models.EquipmentItem(
                equipment_id=equip_id_str,
                type_id=eq_type.id,
                current_location=camera_name,
                last_seen=now
            )
            db.add(item)
            db.commit()
            db.refresh(item)
            
            # Log new detection
            event_engine.publish_event(
                event_type="EquipmentDetection",
                camera_id=camera_id,
                camera_name=camera_name,
                confidence=score,
                details={"equipment_id": equip_id_str, "status": "newly_detected"}
            )
        else:
            # Update location if changed
            if item.current_location != camera_name or (now - item.last_seen.replace(tzinfo=datetime.timezone.utc)).total_seconds() > 60:
                item.current_location = camera_name
                item.last_seen = now
                
                track_log = models.EquipmentTracking(
                    equipment_item_id=item.id,
                    camera_id=camera_id,
                    camera_name=camera_name,
                    timestamp=now
                )
                db.add(track_log)
                db.commit()
                
                # Emit event on location change
                event_engine.publish_event(
                    event_type="EquipmentMovement",
                    camera_id=camera_id,
                    camera_name=camera_name,
                    confidence=score,
                    details={"equipment_id": equip_id_str, "status": "moved"}
                )

    except Exception as e:
        print(f"[EquipmentTracking] Error for {equip_class}: {e}")
        db.rollback()
    finally:
        db.close()


router = APIRouter(prefix="/api", tags=["camera"])


# ─── Camera Worker ────────────────────────────────────────────────────────────
# Background thread reads camera frames, AI-processes them, and notifies
# all connected WebSocket clients (push model — no polling lag).

class CameraWorker:
    def __init__(self):
        self._lock = threading.Lock()
        self._latest_frame: Optional[bytes] = None
        self._thread: Optional[threading.Thread] = None
        self._running = False
        # Event loop + connected WebSocket queues for push delivery
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._client_queues: Set[asyncio.Queue] = set()
        self._client_queues_lock = threading.Lock()

    # ── Public API ────────────────────────────────────────────────────────────

    def start(self, camera_url: str, staff_list: list,
              loop: asyncio.AbstractEventLoop,
              camera_id: Optional[int] = None,
              camera_name: Optional[str] = None):
        self.stop()
        self._loop = loop
        self._running = True
        
        vision_service.update_staff_embeddings(staff_list)
        
        self._thread = threading.Thread(
            target=self._run,
            args=(camera_url, camera_id, camera_name),
            daemon=True
        )
        self._thread.start()

    def stop(self):
        self._running = False
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=3)
        self._latest_frame = None

    def add_client(self, queue: asyncio.Queue):
        with self._client_queues_lock:
            self._client_queues.add(queue)

    def remove_client(self, queue: asyncio.Queue):
        with self._client_queues_lock:
            self._client_queues.discard(queue)

    def get_frame(self) -> Optional[bytes]:
        with self._lock:
            return self._latest_frame

    # ── Background thread ─────────────────────────────────────────────────────

    def _run(self, camera_url: str,
             camera_id: Optional[int] = None,
             camera_name: Optional[str] = None):
        fixed_url = fix_rtsp_url(camera_url)

        target_w     = vision_service.frame_width   # e.g. 640 on CPU, 1280 on GPU
        jpeg_quality = vision_service.jpeg_quality  # e.g. 75 on CPU, 85 on GPU
        target_fps   = vision_service.target_fps    # e.g. 10 on CPU, 25 on GPU
        frame_interval = 1.0 / target_fps
        
        retry_count = 0

        while self._running:
            if isinstance(fixed_url, str) and fixed_url.startswith("rtsp://"):
                os.environ["OPENCV_FFMPEG_CAPTURE_OPTIONS"] = (
                    "rtsp_transport;tcp|stimeout;8000000"
                )
                cap = cv2.VideoCapture(fixed_url, cv2.CAP_FFMPEG)
                cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
            elif str(fixed_url).isdigit():
                cap = cv2.VideoCapture(int(fixed_url))
            else:
                cap = cv2.VideoCapture(fixed_url)

            if not cap.isOpened():
                err = np.zeros((480, 640, 3), dtype=np.uint8)
                cv2.putText(err, "Connection Failed", (50, 240),
                            cv2.FONT_HERSHEY_SIMPLEX, 1.5, (0, 0, 255), 3)
                _, buf = cv2.imencode(".jpg", err)
                self._broadcast(buf.tobytes())
                
                if retry_count == 0:
                    event_engine.publish_event(
                        event_type="CameraOffline",
                        camera_id=camera_id,
                        camera_name=camera_name,
                        details={"error": "Failed to connect to RTSP stream"}
                    )
                
                retry_count += 1
                time.sleep(min(2 ** retry_count, 30))
                continue

            retry_count = 0
            print(f"[Camera] Connected → {camera_url} ({vision_service.backend_label})")

            latest_raw = [None]
            raw_lock   = threading.Lock()
            frame_ready = threading.Event()
            
            reader_running = [True]

            def reader():
                while reader_running[0] and self._running:
                    ret, frame = cap.read()
                    if ret:
                        with raw_lock:
                            latest_raw[0] = frame
                        frame_ready.set()
                    else:
                        reader_running[0] = False

            reader_thread = threading.Thread(target=reader, daemon=True)
            reader_thread.start()

            while reader_running[0] and self._running:
                t0 = time.monotonic()

                if not frame_ready.wait(timeout=2.0):
                    reader_running[0] = False
                    continue
                frame_ready.clear()

                with raw_lock:
                    frame = latest_raw[0]
                if frame is None:
                    continue

                h, w = frame.shape[:2]
                if w != target_w:
                    scale = target_w / w
                    frame = cv2.resize(frame, (target_w, int(h * scale)),
                                       interpolation=cv2.INTER_LINEAR)

                try:
                    processed, face_events, equipment_events = vision_service.process_frame(frame)
                    for ev in face_events:
                        _maybe_mark_attendance(
                            ev["name"], ev["score"],
                            camera_id=camera_id,
                            camera_name=camera_name,
                            has_mask=ev.get("has_mask", True)
                        )
                        
                    for ev in equipment_events:
                        _maybe_track_equipment(
                            equip_class=ev["class"],
                            track_id=ev["track_id"],
                            score=ev["score"],
                            camera_id=camera_id,
                            camera_name=camera_name
                        )
                except Exception as e:
                    import traceback
                    traceback.print_exc()
                    processed = frame

                _, buf = cv2.imencode(
                    ".jpg", processed, [cv2.IMWRITE_JPEG_QUALITY, jpeg_quality]
                )
                jpeg_bytes = buf.tobytes()

                with self._lock:
                    self._latest_frame = jpeg_bytes

                self._broadcast(jpeg_bytes)

                elapsed = time.monotonic() - t0
                sleep = frame_interval - elapsed
                if sleep > 0:
                    time.sleep(sleep)

            cap.release()
            reader_running[0] = False
            if reader_thread.is_alive():
                reader_thread.join(timeout=1.0)
                
            if self._running:
                print("[Camera] Stream dropped. Reconnecting...")
                event_engine.publish_event(
                    event_type="CameraOffline",
                    camera_id=camera_id,
                    camera_name=camera_name,
                    details={"error": "Stream dropped"}
                )

        print("[Camera] Worker stopped.")

    def _broadcast(self, frame: bytes):
        """Push frame to all connected WebSocket clients (thread-safe)."""
        if not self._loop or not self._loop.is_running():
            return
        with self._client_queues_lock:
            queues = list(self._client_queues)
        for q in queues:
            try:
                self._loop.call_soon_threadsafe(q.put_nowait, frame)
            except Exception:
                pass


# Global singleton
camera_worker = CameraWorker()


# ─── URL Fixer ────────────────────────────────────────────────────────────────

def fix_rtsp_url(url: str):
    """
    FFmpeg does NOT URL-decode passwords — decode them here so FFmpeg gets
    the raw characters. Only re-encode @ and : since those break URL parsing.
    """
    if not isinstance(url, str) or not url.startswith("rtsp://"):
        return url

    at_index = url.rfind("@")
    if at_index == -1:
        return url

    prefix = url[:at_index]   # rtsp://user:pass
    suffix = url[at_index:]   # @host:port/path
    cred_str = prefix[7:]     # strip rtsp://

    if ":" in cred_str:
        user, pwd = cred_str.split(":", 1)
        user = unquote(user)
        pwd = unquote(pwd)
        pwd = pwd.replace("@", "%40").replace(":", "%3A")
        user = user.replace("@", "%40").replace(":", "%3A")
        return f"rtsp://{user}:{pwd}{suffix}"

    return url


from routers.staff import load_staff_list


# ─── WebSocket stream endpoint ────────────────────────────────────────────────

@router.websocket("/ws/camera")
async def ws_camera(
    websocket: WebSocket,
    camera_url: Optional[str] = None,
    camera_id: Optional[int] = None,
):
    """
    WebSocket endpoint for live camera streaming.
    Pass either:
      ?camera_id=<id>           — use a saved camera (URL + name resolved from DB)
      ?camera_url=<rtsp://...>  — custom URL (no location tracking)
    """
    await websocket.accept()

    # Resolve camera URL + metadata from DB
    db = SessionLocal()
    try:
        staff_list = load_staff_list(db)
        cam_id_resolved: Optional[int] = None
        cam_name_resolved: Optional[str] = None

        if camera_id:
            cam = db.query(models.Camera).filter(models.Camera.id == camera_id).first()
            if cam:
                camera_url = cam.rtsp_url
                cam_id_resolved = cam.id
                cam_name_resolved = f"{cam.name}" + (f" — {cam.location}" if cam.location else "")
        # If camera_url still None → reject
        if not camera_url:
            await websocket.close(code=4000)
            return
    finally:
        db.close()

    # Start camera worker with location metadata
    loop = asyncio.get_event_loop()
    camera_worker.start(
        camera_url, staff_list, loop,
        camera_id=cam_id_resolved,
        camera_name=cam_name_resolved,
    )

    # Per-client frame queue (maxsize=2 drops stale frames → keeps stream live)
    queue: asyncio.Queue = asyncio.Queue(maxsize=2)
    camera_worker.add_client(queue)

    try:
        while True:
            frame = await asyncio.wait_for(queue.get(), timeout=3.0)
            await websocket.send_bytes(frame)
    except WebSocketDisconnect:
        pass
    except asyncio.TimeoutError:
        pass
    except asyncio.CancelledError:
        raise
    except Exception as e:
        print(f"[WS] Error: {e}")
    finally:
        camera_worker.remove_client(queue)
        print("[WS] Client disconnected.")



# ─── REST helper endpoints (kept for compatibility) ───────────────────────────

@router.get("/camera/start")
def start_camera(camera_url: str, db: Session = Depends(get_db)):
    staff_list = load_staff_list(db)
    loop = asyncio.get_event_loop()
    camera_worker.start(camera_url, staff_list, loop)
    return {"status": "started", "embeddings_loaded": len(staff_list)}


@router.get("/camera/stop")
def stop_camera():
    camera_worker.stop()
    return {"status": "stopped"}


@router.get("/frame")
def get_frame():
    """Single frame endpoint (fallback for non-WS clients)."""
    frame = camera_worker.get_frame()
    if frame is None:
        placeholder = np.zeros((480, 640, 3), dtype=np.uint8)
        cv2.putText(placeholder, "No stream active", (160, 240),
                    cv2.FONT_HERSHEY_SIMPLEX, 1.0, (180, 180, 180), 2)
        _, buf = cv2.imencode(".jpg", placeholder)
        frame = buf.tobytes()

    return Response(
        content=frame,
        media_type="image/jpeg",
        headers={"Cache-Control": "no-store"},
    )
