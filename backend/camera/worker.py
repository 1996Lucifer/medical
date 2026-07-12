import asyncio
import os
import threading
import time
import cv2
import numpy as np
import json
from typing import Optional

from database import SessionLocal
import models
from events import event_engine, is_zone_alerted, set_zone_alert
from camera.vision_worker import vision_process_manager
from camera.audio_worker import audio_process_manager
from camera.compliance_service import compliance_service
from camera.utils import fix_rtsp_url
from camera.attendance_service import _maybe_mark_attendance
from camera.equipment_service import _maybe_track_equipment
from camera.vision_constants import (
    TAMPER_ALERT_COOLDOWN_SEC,
    EMERGENCY_ALERT_COOLDOWN_SEC,
    TAMPER_STD_THRESHOLD,
    TAMPER_MEAN_THRESHOLD,
    TAMPER_LAPLACIAN_THRESHOLD,
)


class CameraWorker:
    def __init__(self):
        self._lock = threading.Lock()
        self._latest_frame: Optional[bytes] = None
        self._thread: Optional[threading.Thread] = None
        self._running = False
        # Event loop + connected WebSocket queues for push delivery
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._client_queues = {}  # Dict[asyncio.Queue, str]
        self._client_queues_lock = threading.Lock()

    # ── Public API ────────────────────────────────────────────────────────────

    def start(
        self,
        camera_url: str,
        staff_list: list,
        loop: asyncio.AbstractEventLoop,
        camera_id: Optional[int] = None,
        camera_name: Optional[str] = None,
    ):
        self.stop()
        self._loop = loop
        self._running = True

        self.camera_key = str(camera_id) if camera_id else camera_url
        vision_process_manager.start_process()
        audio_process_manager.start_process()
        vision_process_manager.update_staff(staff_list)
        vision_process_manager.register_camera(self.camera_key)

        self._thread = threading.Thread(
            target=self._run, args=(camera_url, camera_id, camera_name), daemon=True
        )
        self._thread.start()

    def is_active(self):
        return self._running and self._thread and self._thread.is_alive()

    def stop(self):
        self._running = False
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=3)
        if hasattr(self, "camera_key"):
            vision_process_manager.unregister_camera(self.camera_key)
        self._latest_frame = None
        self._client_queues.clear()

    def add_client(self, queue: asyncio.Queue, mode: str = "ai"):
        with self._client_queues_lock:
            self._client_queues[queue] = mode

    def remove_client(self, queue: asyncio.Queue):
        with self._client_queues_lock:
            self._client_queues.pop(queue, None)

    def get_frame(self) -> Optional[bytes]:
        with self._lock:
            return self._latest_frame

    # ── Background thread ─────────────────────────────────────────────────────

    def _run(
        self,
        camera_url: str,
        camera_id: Optional[int] = None,
        camera_name: Optional[str] = None,
    ):
        fixed_url = fix_rtsp_url(camera_url)

        # Temporary hardcode since we decoupled vision_service from worker process
        target_w = 640
        jpeg_quality = 75
        target_fps = 10
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
                cv2.putText(
                    err,
                    "Connection Failed",
                    (50, 240),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    1.5,
                    (0, 0, 255),
                    3,
                )
                _, buf = cv2.imencode(".jpg", err)
                frame_bytes = buf.tobytes()
                self._broadcast(frame_bytes, frame_bytes)

                if retry_count == 0:
                    event_engine.publish_event(
                        event_type="CameraOffline",
                        camera_id=camera_id,
                        camera_name=camera_name,
                        details={"error": "Failed to connect to RTSP stream"},
                    )

                retry_count += 1
                time.sleep(min(2**retry_count, 30))
                continue

            retry_count = 0
            print(f"[Camera] Connected → {camera_url}")

            latest_raw = [None]
            raw_lock = threading.Lock()
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

            last_rule_check = {}  # Dict[str, float] to throttle rule checks

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
                        cached_rois = (
                            db
                            .query(models.CameraROI)
                            .filter(models.CameraROI.camera_id == camera_id)
                            .all()
                        )
                        db.close()
                    except Exception:
                        pass
                frame_count += 1

                h, w = frame.shape[:2]
                if w != target_w:
                    scale = target_w / w
                    frame = cv2.resize(
                        frame,
                        (target_w, int(h * scale)),
                        interpolation=cv2.INTER_LINEAR,
                    )
                    manage_frame = cv2.resize(
                        manage_frame,
                        (target_w, int(h * scale)),
                        interpolation=cv2.INTER_LINEAR,
                    )

                with self._client_queues_lock:
                    is_ai_active = any(
                        mode == "ai" for mode in self._client_queues.values()
                    )

                try:
                    if is_ai_active:
                        vision_process_manager.process_frame_async(
                            self.camera_key, frame, frame_count
                        )

                        res = vision_process_manager.pop_result(self.camera_key)
                        if res:
                            self.latest_face_events = res.get("face_events", [])
                            self.latest_equipment_events = res.get(
                                "equipment_events", []
                            )
                            self.latest_incident_events = res.get("incident_events", [])
                            self.latest_ppe_events = res.get("ppe_events", [])

                        face_events = getattr(self, "latest_face_events", [])
                        equipment_events = getattr(self, "latest_equipment_events", [])
                        incident_events = getattr(self, "latest_incident_events", [])
                        ppe_events = getattr(self, "latest_ppe_events", [])
                        processed = manage_frame.copy()

                        # Draw AI events
                        for face in face_events:
                            bbox = face["bbox"]
                            color = (
                                (0, 255, 0)
                                if face["name"] != "Unknown"
                                else (0, 0, 255)
                            )
                            cv2.rectangle(
                                processed,
                                (bbox[0], bbox[1]),
                                (bbox[2], bbox[3]),
                                color,
                                1,
                            )
                            label = (
                                f"{face['name']} {face.get('score', 0):.0%}"
                                if face["name"] != "Unknown"
                                else "Unknown"
                            )
                            cv2.putText(
                                processed,
                                label,
                                (bbox[0], max(0, bbox[1] - 10)),
                                cv2.FONT_HERSHEY_SIMPLEX,
                                0.7,
                                color,
                                1,
                            )

                            # Draw body keypoints if available and enabled
                            from camera.vision_constants import DRAW_POSE_SKELETON

                            if DRAW_POSE_SKELETON:
                                kps = face.get("kps")
                                kps_conf = face.get("kps_conf")
                                if kps and kps_conf:
                                    import camera.drawing_utils as drawing_utils

                                    drawing_utils.draw_skeleton(
                                        processed, kps, kps_conf, conf_threshold=0.4
                                    )

                        for eq in equipment_events:
                            bbox = eq["bbox"]
                            label = f"{eq['class']} #{eq.get('track_id', '')}"
                            cv2.rectangle(
                                processed,
                                (bbox[0], bbox[1]),
                                (bbox[2], bbox[3]),
                                (255, 165, 0),
                                1,
                            )
                            cv2.putText(
                                processed,
                                label,
                                (bbox[0], max(0, bbox[1] - 10)),
                                cv2.FONT_HERSHEY_SIMPLEX,
                                0.6,
                                (255, 165, 0),
                                1,
                            )

                        for ppe in ppe_events:
                            bbox = ppe["bbox"]
                            label = f"{ppe['class']} {ppe.get('score', 0):.0%}"
                            color = (255, 255, 0) # Cyan for PPE
                            cv2.rectangle(
                                processed,
                                (bbox[0], bbox[1]),
                                (bbox[2], bbox[3]),
                                color,
                                1,
                            )
                            cv2.putText(
                                processed,
                                label,
                                (bbox[0], max(0, bbox[1] - 10)),
                                cv2.FONT_HERSHEY_SIMPLEX,
                                0.6,
                                color,
                                1,
                            )

                        for inc in incident_events:
                            bbox = inc["bbox"]
                            if inc["type"] == "fall":
                                cv2.rectangle(
                                    processed,
                                    (bbox[0], bbox[1]),
                                    (bbox[2], bbox[3]),
                                    (0, 0, 255),
                                    1,
                                )
                                cv2.putText(
                                    processed,
                                    "FALL DETECTED",
                                    (bbox[0], max(0, bbox[1] - 25)),
                                    cv2.FONT_HERSHEY_SIMPLEX,
                                    0.8,
                                    (0, 0, 255),
                                    1,
                                )
                            elif inc["type"] == "theft":
                                cv2.putText(
                                    processed,
                                    f"SUSPICIOUS: Touching {inc.get('equipment')}",
                                    (bbox[0], max(0, bbox[1] - 45)),
                                    cv2.FONT_HERSHEY_SIMPLEX,
                                    0.7,
                                    (0, 165, 255),
                                    1,
                                )
                            elif inc["type"] == "obscured_face":
                                cv2.rectangle(
                                    processed,
                                    (bbox[0], bbox[1]),
                                    (bbox[2], bbox[3]),
                                    (0, 165, 255),
                                    1,
                                )
                                cv2.putText(
                                    processed,
                                    inc.get("reason", "Obscured"),
                                    (bbox[0], max(0, bbox[1] - 10)),
                                    cv2.FONT_HERSHEY_SIMPLEX,
                                    0.7,
                                    (0, 165, 255),
                                    1,
                                )

                    else:
                        processed = manage_frame.copy()
                        face_events = []
                        equipment_events = []
                        incident_events = []
                        ppe_events = []

                    h, w = processed.shape[:2]

                    # --- TAMPER DETECTION ---
                    if is_ai_active and frame_count > 60:
                        gray_frame = cv2.cvtColor(manage_frame, cv2.COLOR_BGR2GRAY)
                        mean_val, std_val = cv2.meanStdDev(gray_frame)
                        laplacian_var = cv2.Laplacian(gray_frame, cv2.CV_64F).var()

                        # Low contrast (mostly uniform color like a hand), extremely dark, or extremely blurry
                        if (
                            std_val[0][0] < TAMPER_STD_THRESHOLD
                            or mean_val[0][0] < TAMPER_MEAN_THRESHOLD
                            or laplacian_var < TAMPER_LAPLACIAN_THRESHOLD
                        ):
                            cv2.putText(
                                processed,
                                "CAMERA TAMPERED / BLOCKED",
                                (20, h // 2),
                                cv2.FONT_HERSHEY_SIMPLEX,
                                1.2,
                                (0, 0, 255),
                                3,
                            )
                            tamper_key = f"{camera_name}_tamper"
                            if not is_zone_alerted(tamper_key):
                                event_engine.publish_event(
                                    event_type="SecurityAlert",
                                    camera_id=camera_id,
                                    camera_name=camera_name,
                                    confidence=1.0,
                                    details={
                                        "alert": "Camera tampers or is blocked (low contrast/dark/blurry)"
                                    },
                                )
                                set_zone_alert(
                                    tamper_key, duration_sec=TAMPER_ALERT_COOLDOWN_SEC
                                )
                    # ------------------------

                    # Parse ROI polygons
                    parsed_rois = []
                    for roi in cached_rois:
                        try:
                            points = json.loads(roi.points)
                            pts = np.array(
                                [[int(p["x"] * w), int(p["y"] * h)] for p in points],
                                np.int32,
                            )
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
                        active_rules = (
                            db
                            .query(models.SecurityRule)
                            .filter(models.SecurityRule.is_active == True)
                            .all()
                        )
                        db.close()

                    for ev in face_events:
                        zone_name = get_zone_for_bbox(ev["bbox"])
                        effective_cam_name = (
                            f"{camera_name} - {zone_name}" if zone_name else camera_name
                        )

                        is_new_session = _maybe_mark_attendance(
                            ev["name"],
                            ev.get("score", 1.0),
                            camera_id=camera_id,
                            camera_name=effective_cam_name,
                            has_mask=ev.get("has_mask", True),
                        )

                        now_t = time.monotonic()
                        rule_throttle_key = f"{ev['name']}_{effective_cam_name}"
                        last_check = last_rule_check.get(rule_throttle_key, 0)

                        # We always want to check compliance if active_rules exist OR if the person is Unknown (potential intruder)
                        needs_check = bool(active_rules) or ev["name"] == "Unknown"

                        # Trigger dynamic rules check every 1 second since it's native now
                        if needs_check and (
                            is_new_session or (now_t - last_check > 1.0)
                        ):
                            valid_rules = [
                                r
                                for r in active_rules
                                if not r.target_area
                                or (
                                    effective_cam_name
                                    and r.target_area.lower()
                                    in effective_cam_name.lower()
                                )
                                or (
                                    zone_name
                                    and r.target_area.lower() == zone_name.lower()
                                )
                            ]
                            if self._loop:
                                last_rule_check[rule_throttle_key] = now_t
                                import asyncio

                                # Crop the image to the person's bounding box + margin to speed up VLM inference
                                bbox = ev.get("bbox", None)
                                frame_to_eval = processed.copy()
                                if bbox is not None:
                                    h, w = frame_to_eval.shape[:2]
                                    x1, y1, x2, y2 = map(int, bbox)
                                    margin_x = int((x2 - x1) * 2.0)
                                    margin_y = int((y2 - y1) * 2.0)
                                    nx1 = max(0, x1 - margin_x)
                                    ny1 = max(0, y1 - margin_y)
                                    nx2 = min(w, x2 + margin_x)
                                    ny2 = min(h, y2 + margin_y)
                                    if nx2 > nx1 and ny2 > ny1:
                                        frame_to_eval = frame_to_eval[ny1:ny2, nx1:nx2]

                                asyncio.run_coroutine_threadsafe(
                                    compliance_service.evaluate_dynamic_rules(
                                        frame_to_eval,
                                        valid_rules,
                                        ev["name"],
                                        effective_cam_name,
                                        ev.get("has_mask", False),
                                        ev.get("has_gloves", False),
                                    ),
                                    self._loop,
                                )

                    for ev in equipment_events:
                        zone_name = get_zone_for_bbox(ev["bbox"])
                        effective_cam_name = (
                            f"{camera_name} - {zone_name}" if zone_name else camera_name
                        )
                        _maybe_track_equipment(
                            equip_class=ev["class"],
                            track_id=ev["track_id"],
                            score=ev["score"],
                            camera_id=camera_id,
                            camera_name=effective_cam_name,
                        )

                    for ev in incident_events:
                        incident_type = ev.get("type")
                        zone_name = get_zone_for_bbox(ev["bbox"])
                        effective_cam_name = (
                            f"{camera_name} - {zone_name}" if zone_name else camera_name
                        )

                        if incident_type == "fall":
                            alert_key = f"{effective_cam_name}_fall"
                            if not is_zone_alerted(alert_key):
                                event_engine.publish_event(
                                    event_type="MedicalEmergency",
                                    camera_id=camera_id,
                                    camera_name=effective_cam_name,
                                    details={"alert": "Fall detected."},
                                )
                                from camera.audio_service import audio_service

                                audio_service.speak(
                                    camera_url,
                                    "Emergency: Fall detected. Please assist.",
                                    vendor="tapo",
                                )
                                set_zone_alert(
                                    alert_key, duration_sec=EMERGENCY_ALERT_COOLDOWN_SEC
                                )

                        elif incident_type == "theft":
                            alert_key = f"{effective_cam_name}_theft"
                            if not is_zone_alerted(alert_key):
                                event_engine.publish_event(
                                    event_type="SecurityAlert",
                                    camera_id=camera_id,
                                    camera_name=effective_cam_name,
                                    details={
                                        "alert": f"Unauthorized interaction with {ev.get('equipment')}."
                                    },
                                )
                                from camera.audio_service import audio_service

                                audio_service.speak(
                                    camera_url,
                                    "Warning: Unauthorized interaction with equipment detected.",
                                    vendor="tapo",
                                )
                                set_zone_alert(
                                    alert_key, duration_sec=EMERGENCY_ALERT_COOLDOWN_SEC
                                )

                    # Render ROIs on processed frame and manage frame
                    if parsed_rois:
                        overlay = processed.copy()
                        manage_overlay = manage_frame.copy()
                        for z_name, pts in parsed_rois:
                            effective_cam_name = f"{camera_name} - {z_name}"
                            is_alert = is_zone_alerted(effective_cam_name)
                            fill_color = (0, 0, 255) if is_alert else (160, 200, 0)
                            cv2.fillPoly(overlay, [pts], fill_color)
                            cv2.fillPoly(manage_overlay, [pts], fill_color)

                        cv2.addWeighted(overlay, 0.25, processed, 0.75, 0, processed)
                        cv2.addWeighted(
                            manage_overlay, 0.25, manage_frame, 0.75, 0, manage_frame
                        )

                        for z_name, pts in parsed_rois:
                            effective_cam_name = f"{camera_name} - {z_name}"
                            is_alert = is_zone_alerted(effective_cam_name)
                            border_color = (0, 0, 255) if is_alert else (255, 200, 0)

                            # Draw on AI processed frame
                            cv2.polylines(
                                processed,
                                [pts],
                                isClosed=True,
                                color=border_color,
                                thickness=2 if is_alert else 1,
                            )
                            cv2.putText(
                                processed,
                                z_name,
                                (pts[0][0][0], pts[0][0][1] - 10),
                                cv2.FONT_HERSHEY_SIMPLEX,
                                0.7,
                                border_color,
                                1,
                            )

                            # Draw on Manage frame
                            cv2.polylines(
                                manage_frame,
                                [pts],
                                isClosed=True,
                                color=border_color,
                                thickness=2 if is_alert else 1,
                            )
                            cv2.putText(
                                manage_frame,
                                z_name,
                                (pts[0][0][0], pts[0][0][1] - 10),
                                cv2.FONT_HERSHEY_SIMPLEX,
                                0.7,
                                border_color,
                                1,
                            )

                except Exception:
                    import traceback

                    traceback.print_exc()
                    processed = frame
                    manage_frame = frame

                with self._lock:
                    self._latest_frame = (
                        processed.copy()
                    )  # keep a raw copy for snapshots if needed

                self._broadcast(processed, manage_frame)

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
                    details={"error": "Stream dropped"},
                )

        print("[Camera] Worker stopped.")

    def _broadcast(self, processed_np, manage_frame_np):
        """Push frame to all connected clients (thread-safe). Converts to JPEG only if needed."""
        if not self._loop or not self._loop.is_running():
            return
        with self._client_queues_lock:
            clients = list(self._client_queues.items())

        if not clients:
            return

        has_ws_ai = any(mode == "ai" for _, mode in clients)
        has_ws_manage = any(mode == "manage" for _, mode in clients)

        ai_jpeg = None
        manage_jpeg = None

        if has_ws_ai:
            import cv2

            _, buf = cv2.imencode(".jpg", processed_np, [cv2.IMWRITE_JPEG_QUALITY, 80])
            ai_jpeg = buf.tobytes()
        if has_ws_manage:
            import cv2

            _, buf = cv2.imencode(
                ".jpg", manage_frame_np, [cv2.IMWRITE_JPEG_QUALITY, 80]
            )
            manage_jpeg = buf.tobytes()

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
            if mode == "ai":
                item = ai_jpeg
            elif mode == "manage":
                item = manage_jpeg
            elif mode == "webrtc_ai":
                item = processed_np
            elif mode == "webrtc_manage":
                item = manage_frame_np
            else:
                continue

            if item is not None:
                self._loop.call_soon_threadsafe(_push, q, item)


active_workers = {}  # Dict[str, CameraWorker]
