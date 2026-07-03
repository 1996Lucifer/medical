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

from database import get_db, SessionLocal
import models
from camera.vision_service import vision_service
from camera.compliance_service import compliance_service
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
                return False
            _last_db_write[throttle_key] = now

        event_engine.publish_event(
            event_type="UnknownFaceDetected",
            camera_id=camera_id,
            camera_name=camera_name,
            confidence=score,
            details={"status": "detected"}
        )
        return True

    now = datetime.datetime.now(tz=datetime.timezone.utc)

    # In-memory throttle — skip DB entirely if we wrote recently
    with _last_db_write_lock:
        last_write = _last_db_write.get(name)
        if last_write and (now - last_write).total_seconds() < LAST_SEEN_FREQ_SEC:
            return False
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
            return True
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
            return False

    except Exception as e:
        print(f"[Attendance] Error for {name}: {e}")
        db.rollback()
        return False
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
        self._client_queues = {} # Dict[asyncio.Queue, str]
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

    def is_active(self):
        return self._running and self._thread and self._thread.is_alive()

    def stop(self):
        self._running = False
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=3)
        self._latest_frame = None
        self._client_queues.clear()

    def add_client(self, queue: asyncio.Queue, mode: str = 'ai'):
        with self._client_queues_lock:
            self._client_queues[queue] = mode

    def remove_client(self, queue: asyncio.Queue):
        with self._client_queues_lock:
            self._client_queues.pop(queue, None)

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
                frame_bytes = buf.tobytes()
                self._broadcast(frame_bytes, frame_bytes)

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

            cached_rois = []
            frame_count = 0

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
                manage_frame = frame.copy()

                if frame_count % 30 == 0:
                    try:
                        db = SessionLocal()
                        cached_rois = db.query(models.CameraROI).filter(models.CameraROI.camera_id == camera_id).all()
                        db.close()
                    except Exception:
                        pass
                frame_count += 1

                h, w = frame.shape[:2]
                if w != target_w:
                    scale = target_w / w
                    frame = cv2.resize(frame, (target_w, int(h * scale)),
                                       interpolation=cv2.INTER_LINEAR)
                    manage_frame = cv2.resize(manage_frame, (target_w, int(h * scale)),
                                       interpolation=cv2.INTER_LINEAR)

                with self._client_queues_lock:
                    is_ai_active = any(mode == 'ai' for mode in self._client_queues.values())

                try:
                    if is_ai_active:
                        processed, face_events, equipment_events = vision_service.process_frame(frame)
                    else:
                        processed = manage_frame.copy()
                        face_events = []
                        equipment_events = []

                    h, w = processed.shape[:2]

                    # --- TAMPER DETECTION ---
                    if is_ai_active and frame_count > 60:
                        gray_frame = cv2.cvtColor(manage_frame, cv2.COLOR_BGR2GRAY)
                        mean_val, std_val = cv2.meanStdDev(gray_frame)
                        laplacian_var = cv2.Laplacian(gray_frame, cv2.CV_64F).var()
                        
                        # Low contrast (mostly uniform color like a hand), extremely dark, or extremely blurry
                        if std_val[0][0] < 35.0 or mean_val[0][0] < 20.0 or laplacian_var < 50.0:
                            cv2.putText(processed, "CAMERA TAMPERED / BLOCKED", (20, h//2), cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0, 0, 255), 3)
                            from events import is_zone_alerted, set_zone_alert
                            tamper_key = f"{camera_name}_tamper"
                            if not is_zone_alerted(tamper_key):
                                event_engine.publish_event(
                                    event_type="SecurityAlert",
                                    camera_id=camera_id,
                                    camera_name=camera_name,
                                    confidence=1.0,
                                    details={"alert": "Camera tampers or is blocked (low contrast/dark/blurry)"}
                                )
                                set_zone_alert(tamper_key, duration_sec=10.0)
                    # ------------------------


                    # Parse ROI polygons
                    import json
                    parsed_rois = []
                    for roi in cached_rois:
                        try:
                            points = json.loads(roi.points)
                            pts = np.array([[int(p['x']*w), int(p['y']*h)] for p in points], np.int32)
                            pts = pts.reshape((-1, 1, 2))
                            parsed_rois.append((roi.zone_name, pts))
                        except Exception:
                            pass

                    # Helper to find zone for a bbox
                    def get_zone_for_bbox(bbox):
                        if not parsed_rois:
                            return None
                        bc_x = (bbox[0] + bbox[2]) // 2
                        bc_y = bbox[3]
                        for z_name, pts in parsed_rois:
                            if cv2.pointPolygonTest(pts, (bc_x, bc_y), False) >= 0:
                                return z_name
                        return None

                    active_rules = []
                    if face_events:
                        db = SessionLocal()
                        active_rules = db.query(models.SecurityRule).filter(models.SecurityRule.is_active == True).all()
                        db.close()

                    for ev in face_events:
                        zone_name = get_zone_for_bbox(ev["bbox"])
                        effective_cam_name = f"{camera_name} - {zone_name}" if zone_name else camera_name

                        if zone_name and ev["name"] == "Unknown":
                            from events import set_zone_alert, is_zone_alerted
                            if not is_zone_alerted(effective_cam_name):
                                warning_text = f"Unauthorized person detected in {zone_name}"
                                event_engine.publish_event(
                                    event_type="SpokenWarning",
                                    camera_id=camera_id,
                                    camera_name=effective_cam_name,
                                    confidence=ev["score"],
                                    details={"warning": warning_text}
                                )
                                from camera.audio_service import audio_service
                                # Defaulting to tapo for now since we know it's a Tapo camera
                                audio_service.speak(camera_url, warning_text, vendor="tapo")
                                
                                # Trigger Home Assistant siren
                                try:
                                    db_cam = SessionLocal()
                                    camera = db_cam.query(models.Camera).filter(models.Camera.id == camera_id).first()
                                    if camera and camera.ha_entity_id:
                                        from ha_service import trigger_siren
                                        trigger_siren(camera.ha_entity_id)
                                    db_cam.close()
                                except Exception as e:
                                    print(f"[CameraWorker] Failed to trigger siren: {e}")
                                
                                set_zone_alert(effective_cam_name, duration_sec=5.0)

                        is_new_session = _maybe_mark_attendance(
                            ev["name"], ev["score"],
                            camera_id=camera_id,
                            camera_name=effective_cam_name,
                            has_mask=ev.get("has_mask", True)
                        )

                        # Trigger dynamic rules check ONLY when first entering the zone
                        if is_new_session and active_rules:
                            valid_rules = [
                                r for r in active_rules
                                if not r.target_area
                                or (effective_cam_name and r.target_area.lower() in effective_cam_name.lower())
                                or (zone_name and r.target_area.lower() == zone_name.lower())
                            ]
                            if valid_rules and self._loop:
                                import asyncio
                                asyncio.run_coroutine_threadsafe(
                                    compliance_service.evaluate_dynamic_rules(manage_frame.copy(), valid_rules, ev["name"], effective_cam_name),
                                    self._loop
                                )

                    for ev in equipment_events:
                        zone_name = get_zone_for_bbox(ev["bbox"])
                        effective_cam_name = f"{camera_name} - {zone_name}" if zone_name else camera_name
                        _maybe_track_equipment(
                            equip_class=ev["class"],
                            track_id=ev["track_id"],
                            score=ev["score"],
                            camera_id=camera_id,
                            camera_name=effective_cam_name
                        )

                    # Render ROIs on processed frame and manage frame
                    if parsed_rois:
                        overlay = processed.copy()
                        manage_overlay = manage_frame.copy()
                        from events import is_zone_alerted
                        for z_name, pts in parsed_rois:
                            effective_cam_name = f"{camera_name} - {z_name}"
                            is_alert = is_zone_alerted(effective_cam_name)
                            fill_color = (0, 0, 255) if is_alert else (160, 200, 0)
                            cv2.fillPoly(overlay, [pts], fill_color)
                            cv2.fillPoly(manage_overlay, [pts], fill_color)

                        cv2.addWeighted(overlay, 0.25, processed, 0.75, 0, processed)
                        cv2.addWeighted(manage_overlay, 0.25, manage_frame, 0.75, 0, manage_frame)

                        for z_name, pts in parsed_rois:
                            effective_cam_name = f"{camera_name} - {z_name}"
                            is_alert = is_zone_alerted(effective_cam_name)
                            border_color = (0, 0, 255) if is_alert else (255, 200, 0)
                            
                            # Draw on AI processed frame
                            cv2.polylines(processed, [pts], isClosed=True, color=border_color, thickness=3 if is_alert else 2)
                            cv2.putText(processed, z_name, (pts[0][0][0], pts[0][0][1] - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.7, border_color, 2)
                            
                            # Draw on Manage frame
                            cv2.polylines(manage_frame, [pts], isClosed=True, color=border_color, thickness=3 if is_alert else 2)
                            cv2.putText(manage_frame, z_name, (pts[0][0][0], pts[0][0][1] - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.7, border_color, 2)

                except Exception as e:
                    import traceback
                    traceback.print_exc()
                    processed = frame
                    manage_frame = frame

                _, buf_ai = cv2.imencode(".jpg", processed, [cv2.IMWRITE_JPEG_QUALITY, jpeg_quality])
                _, buf_manage = cv2.imencode(".jpg", manage_frame, [cv2.IMWRITE_JPEG_QUALITY, jpeg_quality])
                jpeg_bytes = buf_ai.tobytes()
                manage_bytes = buf_manage.tobytes()

                with self._lock:
                    self._latest_frame = jpeg_bytes

                self._broadcast(jpeg_bytes, manage_bytes)

                elapsed = time.monotonic() - t0
                sleep = frame_interval - elapsed
                if sleep > 0:
                    time.sleep(sleep)

            reader_running[0] = False
            if reader_thread.is_alive():
                reader_thread.join(timeout=10.0)
            cap.release()

            if self._running:
                print("[Camera] Stream dropped. Reconnecting...")
                event_engine.publish_event(
                    event_type="CameraOffline",
                    camera_id=camera_id,
                    camera_name=camera_name,
                    details={"error": "Stream dropped"}
                )

        print("[Camera] Worker stopped.")

    def _broadcast(self, ai_frame: bytes, manage_frame: bytes):
        """Push frame to all connected WebSocket clients (thread-safe)."""
        if not self._loop or not self._loop.is_running():
            return
        with self._client_queues_lock:
            clients = list(self._client_queues.items())
            
        def _push(q, item):
            import asyncio
            try:
                q.put_nowait(item)
            except asyncio.QueueFull:
                try:
                    q.get_nowait()
                    q.put_nowait(item)
                except Exception:
                    pass

        for q, mode in clients:
            frame_to_send = ai_frame if mode == 'ai' else manage_frame
            try:
                self._loop.call_soon_threadsafe(_push, q, frame_to_send)
            except Exception:
                pass


active_workers = {} # Dict[str, CameraWorker]


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
    mode: str = 'ai'
):
    """
    WebSocket endpoint for live camera streaming.
    Pass either:
      ?camera_id=<id>           — use a saved camera (URL + name resolved from DB)
      ?camera_url=<rtsp://...>  — custom URL (no location tracking)
      &mode=ai|manage           — controls whether AI boxes are drawn
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

    # Start camera worker for this specific mode
    loop = asyncio.get_event_loop()
    worker_key = f"{cam_id_resolved}_{mode}"
    
    if worker_key not in active_workers:
        active_workers[worker_key] = CameraWorker()
        
    worker = active_workers[worker_key]
    if not worker.is_active():
        worker.start(
            camera_url, staff_list, loop,
            camera_id=cam_id_resolved,
            camera_name=cam_name_resolved,
        )

    # Per-client frame queue (maxsize=2 drops stale frames → keeps stream live)
    queue: asyncio.Queue = asyncio.Queue(maxsize=2)
    worker.add_client(queue, mode)


    # Pre-compute a loading frame
    import cv2
    import numpy as np
    loading_img = np.zeros((480, 640, 3), dtype=np.uint8)
    cv2.putText(loading_img, "Connecting to camera...", (50, 240), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (255, 255, 255), 2)
    _, loading_buf = cv2.imencode(".jpg", loading_img)
    loading_frame_bytes = loading_buf.tobytes()

    try:
        while True:
            try:
                frame = await asyncio.wait_for(queue.get(), timeout=2.0)
                await websocket.send_bytes(frame)
            except asyncio.TimeoutError:
                # Send loading frame to keep connection alive and show feedback
                await websocket.send_bytes(loading_frame_bytes)
    except WebSocketDisconnect:

        pass
    except asyncio.TimeoutError:
        pass
    except asyncio.CancelledError:
        raise
    except Exception as e:
        print(f"[WS] Error: {e}")
    finally:
        worker.remove_client(queue)
        print("[WS] Client disconnected.")
        # If no clients left for this worker, stop the thread
        if not worker._client_queues:
            worker.stop()
            active_workers.pop(worker_key, None)




@router.websocket("/cameras/ws/status")
async def ws_cameras_status(websocket: WebSocket, db: Session = Depends(get_db)):
    """WebSocket endpoint to push camera online/offline status periodically."""
    await websocket.accept()
    try:
        while True:
            import urllib.parse
            async def _check_rtsp(cam_id: int, url: str) -> tuple[int, bool]:
                try:
                    parsed = urllib.parse.urlparse(url)
                    host = parsed.hostname
                    port = parsed.port or 554
                    if not host:
                        return cam_id, False
                    fut = asyncio.open_connection(host, port)
                    reader, writer = await asyncio.wait_for(fut, timeout=2.0)
                    writer.close()
                    await writer.wait_closed()
                    return cam_id, True
                except Exception:
                    return cam_id, False
            
            cameras = db.query(models.Camera).all()
            tasks = [_check_rtsp(c.id, c.rtsp_url) for c in cameras]
            results = await asyncio.gather(*tasks)
            status_map = {str(cam_id): status for cam_id, status in results}
            await websocket.send_json(status_map)
            await asyncio.sleep(15)
    except WebSocketDisconnect:
        pass
    except Exception as e:
        print(f"[Status WS] Error: {e}")


# ─── REST helper endpoints (kept for compatibility) ───────────────────────────

@router.get("/camera/start")
def start_camera(camera_url: str, db: Session = Depends(get_db)):
    # Deprecated / unused standalone start. 
    return {"status": "deprecated"}


@router.get("/camera/stop")
def stop_camera():
    for w in active_workers.values():
        w.stop()
    active_workers.clear()
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

import socket
from urllib.parse import urlparse

@router.get("/cameras/{camera_id}/status")
def get_camera_status(camera_id: int, db: Session = Depends(get_db)):
    cam = db.query(models.Camera).filter(models.Camera.id == camera_id).first()
    if not cam:
        raise HTTPException(status_code=404, detail="Camera not found")

    try:
        # Fast TCP check on the RTSP host and port
        parsed = urlparse(cam.rtsp_url)
        host = parsed.hostname
        port = parsed.port or 554
        if not host:
            return {"status": "offline"}

        with socket.create_connection((host, port), timeout=2.0):
            return {"status": "online"}
    except Exception:
        return {"status": "offline"}

import subprocess

@router.get("/cameras/{camera_id}/snapshot")
def get_camera_snapshot(camera_id: int, db: Session = Depends(get_db)):
    cam = db.query(models.Camera).filter(models.Camera.id == camera_id).first()
    if not cam:
        raise HTTPException(status_code=404, detail="Camera not found")

    try:
        # Use OpenCV to grab a single frame
        # Set options to prefer TCP and a 5-second timeout to match the old behavior
        os.environ["OPENCV_FFMPEG_CAPTURE_OPTIONS"] = "rtsp_transport;tcp|stimeout;5000000"

        cap = cv2.VideoCapture(cam.rtsp_url, cv2.CAP_FFMPEG)
        if not cap.isOpened():
            raise HTTPException(status_code=504, detail="Camera snapshot timed out or connection failed")

        ret, frame = cap.read()
        cap.release()

        if ret and frame is not None:
            success, encoded_image = cv2.imencode('.jpg', frame)
            if success:
                return Response(content=encoded_image.tobytes(), media_type="image/jpeg")
            raise HTTPException(status_code=503, detail="Failed to encode frame")
        else:
            raise HTTPException(status_code=503, detail="Failed to grab frame using OpenCV")

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
