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
from camera.compliance_engine import compliance_engine
from camera.utils import fix_rtsp_url
from camera.attendance_service import _maybe_mark_attendance
from camera.equipment_service import _maybe_track_equipment
from camera.vision_constants import (
    TAMPER_ALERT_COOLDOWN_SEC,
    EMERGENCY_ALERT_COOLDOWN_SEC,
    TAMPER_STD_THRESHOLD,
    TAMPER_MEAN_THRESHOLD,
    TAMPER_LAPLACIAN_THRESHOLD,
    ZONE_TYPE_RESTRICTED,
    get_runtime_vision_config,
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
        self._last_staff_zone = {}  # staff_name -> (camera_id, zone_name, zone_type)
        self._display_tracks = {}

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
        self._last_staff_zone.clear()
        self._display_tracks.clear()

    def add_client(self, queue: asyncio.Queue, mode: str = "ai"):
        with self._client_queues_lock:
            self._client_queues[queue] = mode

    def remove_client(self, queue: asyncio.Queue):
        with self._client_queues_lock:
            self._client_queues.pop(queue, None)

    def get_frame(self) -> Optional[bytes]:
        with self._lock:
            return self._latest_frame

    # ── Low-latency display tracking ─────────────────────────────────────────

    @staticmethod
    def _bbox_center(bbox):
        return ((bbox[0] + bbox[2]) / 2.0, (bbox[1] + bbox[3]) / 2.0)

    @staticmethod
    def _bbox_size(bbox):
        return max(1.0, float(bbox[2] - bbox[0]), float(bbox[3] - bbox[1]))

    @staticmethod
    def _clip_bbox(bbox, frame_shape):
        h, w = frame_shape[:2]
        x1 = max(0.0, min(float(w - 1), float(bbox[0])))
        y1 = max(0.0, min(float(h - 1), float(bbox[1])))
        x2 = max(0.0, min(float(w - 1), float(bbox[2])))
        y2 = max(0.0, min(float(h - 1), float(bbox[3])))
        if x2 - x1 < 2.0 or y2 - y1 < 2.0:
            return None
        return [int(round(x1)), int(round(y1)), int(round(x2)), int(round(y2))]

    @staticmethod
    def _event_key(kind, event):
        if kind == "face":
            tid = event.get("tid")
            return ("tid", tid) if tid is not None and tid != -1 else None
        if kind == "equipment":
            tid = event.get("track_id")
            return ("equipment", event.get("class"), tid) if tid is not None and tid != -1 else None
        return None

    def _match_display_track(self, tracks, kind, event):
        key = self._event_key(kind, event)
        if key is not None and key in tracks:
            return key, tracks[key]

        bbox = event.get("bbox")
        if not bbox:
            return None, None
        cx, cy = self._bbox_center(bbox)
        best_key = None
        best_track = None
        best_rel_dist = 999.0
        for track_key, track in tracks.items():
            if track.get("kind") != kind:
                continue
            if kind == "ppe" and track.get("class") != event.get("class"):
                continue
            tcx, tcy = self._bbox_center(track["bbox"])
            rel_dist = (((cx - tcx) ** 2 + (cy - tcy) ** 2) ** 0.5) / self._bbox_size(bbox)
            if rel_dist < best_rel_dist:
                best_key = track_key
                best_track = track
                best_rel_dist = rel_dist
        if best_track is not None and best_rel_dist <= (1.25 if kind == "ppe" else 1.8):
            return best_key, best_track
        return None, None

    def _smooth_event_group(self, camera_key, kind, events, frame_shape, now):
        state = self._display_tracks.setdefault(camera_key, {})
        tracks = state.setdefault(kind, {})
        used = set()
        smoothed_events = []

        for event in events:
            bbox = event.get("bbox")
            if not bbox or len(bbox) != 4:
                continue
            key, track = self._match_display_track(tracks, kind, event)
            if key is None:
                base_key = self._event_key(kind, event)
                key = base_key if base_key is not None else ("auto", kind, state.get("next_id", 1))
                state["next_id"] = int(state.get("next_id", 1)) + 1

            raw_box = [float(v) for v in bbox]
            if track:
                dt = max(0.015, min(0.30, now - float(track.get("updated_at", now))))
                prev = track["bbox"]
                pcx, pcy = self._bbox_center(prev)
                rcx, rcy = self._bbox_center(raw_box)
                measured_vx = (rcx - pcx) / dt
                measured_vy = (rcy - pcy) / dt
                vx = (float(track.get("vx", 0.0)) * 0.45) + (measured_vx * 0.55)
                vy = (float(track.get("vy", 0.0)) * 0.45) + (measured_vy * 0.55)
                pred_box = [
                    prev[0] + vx * dt,
                    prev[1] + vy * dt,
                    prev[2] + vx * dt,
                    prev[3] + vy * dt,
                ]
                pred_cx, pred_cy = self._bbox_center(pred_box)
                residual = (((rcx - pred_cx) ** 2 + (rcy - pred_cy) ** 2) ** 0.5) / self._bbox_size(raw_box)
                gain = 0.90 if residual > 0.45 else 0.68 if residual > 0.18 else 0.38
                filtered = [
                    pred_box[i] + ((raw_box[i] - pred_box[i]) * gain)
                    for i in range(4)
                ]
            else:
                vx = vy = 0.0
                filtered = raw_box

            clipped = self._clip_bbox(filtered, frame_shape)
            if clipped is None:
                continue

            updated_event = dict(event)
            updated_event["raw_bbox"] = [int(round(v)) for v in raw_box]
            updated_event["bbox"] = clipped
            updated_event["track_vx_sec"] = vx
            updated_event["track_vy_sec"] = vy
            updated_event["track_ts"] = now
            smoothed_events.append(updated_event)
            tracks[key] = {
                "kind": kind,
                "bbox": [float(v) for v in clipped],
                "event": updated_event,
                "class": event.get("class"),
                "vx": vx,
                "vy": vy,
                "updated_at": now,
                "last_seen": now,
                "misses": 0,
            }
            used.add(key)

        for key, track in list(tracks.items()):
            if key in used:
                continue
            age = now - float(track.get("last_seen", now))
            if age > 0.55:
                del tracks[key]
                continue
            dt = max(0.015, min(0.18, now - float(track.get("updated_at", now))))
            vx = float(track.get("vx", 0.0)) * 0.72
            vy = float(track.get("vy", 0.0)) * 0.72
            coasted = [
                track["bbox"][0] + vx * dt,
                track["bbox"][1] + vy * dt,
                track["bbox"][2] + vx * dt,
                track["bbox"][3] + vy * dt,
            ]
            clipped = self._clip_bbox(coasted, frame_shape)
            if clipped is None:
                del tracks[key]
                continue
            track["bbox"] = [float(v) for v in clipped]
            track["vx"] = vx
            track["vy"] = vy
            track["updated_at"] = now
            track["misses"] = int(track.get("misses", 0)) + 1
            coasted_event = dict(track.get("event", {}))
            coasted_event["bbox"] = clipped
            coasted_event["_coasted"] = True
            coasted_event["track_vx_sec"] = vx
            coasted_event["track_vy_sec"] = vy
            coasted_event["track_ts"] = now
            track["event"] = coasted_event
            smoothed_events.append(coasted_event)

        return smoothed_events

    def _smooth_display_events(
        self,
        camera_key,
        face_events,
        equipment_events,
        incident_events,
        ppe_events,
        frame_shape,
    ):
        now = time.time()
        return (
            self._smooth_event_group(camera_key, "face", face_events, frame_shape, now),
            self._smooth_event_group(camera_key, "equipment", equipment_events, frame_shape, now),
            self._smooth_event_group(camera_key, "incident", incident_events, frame_shape, now),
            self._smooth_event_group(camera_key, "ppe", ppe_events, frame_shape, now),
        )

    @staticmethod
    def _draw_face_event(frame, ev):
        bbox = ev.get("bbox")
        if not bbox:
            return
        x1, y1, x2, y2 = bbox
        name = ev.get("name", "Unknown")
        zone_type = ev.get("zone_type", "observation")
        is_verified = bool(ev.get("is_verified", False))

        has_mask = bool(ev.get("has_mask", False))
        has_left = bool(ev.get("has_left_glove", False))
        has_right = bool(ev.get("has_right_glove", False))
        has_gloves = bool(ev.get("has_gloves", False)) or (has_left and has_right) or (has_left or has_right)

        m_text = "MASK ✓" if has_mask else "NO MASK ❌"
        g_text = "GLOVES ✓" if has_gloves else "NO GLOVES ❌"
        ppe_status = f"{m_text} | {g_text}"

        if name == "Unknown":
            color = (0, 0, 255)
            status = f"UNAUTHORIZED ({ppe_status})"
        elif zone_type == ZONE_TYPE_RESTRICTED:
            if is_verified or (has_mask and has_gloves):
                color = (0, 255, 0)
                status = f"VERIFIED ✓ ({ppe_status})"
            else:
                color = (0, 0, 255)
                status = f"RESTRICTED VIOLATION 🚨 ({ppe_status})"
        elif is_verified:
            color = (0, 255, 0)
            status = f"VERIFIED ✓ ({ppe_status})"
        else:
            if not has_mask or not has_gloves:
                color = (0, 165, 255) if (has_mask or has_gloves) else (0, 0, 255)
            else:
                color = (0, 255, 0)
            status = ppe_status

        cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
        label = f"#{ev.get('tid', '')} {name}".strip()
        score = float(ev.get("score", 0.0) or 0.0)
        if score > 0:
            label += f" {score:.0%}"
        cv2.putText(frame, label, (x1, max(0, y1 - 10)), cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)
        if status:
            cv2.putText(frame, status, (x1, min(frame.shape[0] - 5, y2 + 20)), cv2.FONT_HERSHEY_SIMPLEX, 0.55, color, 2)

    # ── Background thread ─────────────────────────────────────────────────────

    def _run(
        self,
        camera_url: str,
        camera_id: Optional[int] = None,
        camera_name: Optional[str] = None,
    ):
        fixed_url = fix_rtsp_url(camera_url)

        runtime_config = get_runtime_vision_config()
        target_w = runtime_config["frame_width"]
        jpeg_quality = runtime_config["jpeg_quality"]
        self._jpeg_quality = jpeg_quality
        target_fps = runtime_config["target_fps"]
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
                self._broadcast(err, err)

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
                        mode == "ai" or mode == "webrtc_ai" for mode in self._client_queues.values()
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
                        
                        (
                            face_events,
                            equipment_events,
                            incident_events,
                            ppe_events,
                        ) = self._smooth_display_events(
                            self.camera_key,
                            face_events,
                            equipment_events,
                            incident_events,
                            ppe_events,
                            manage_frame.shape,
                        )

                        # Draw on the current live frame. Inference can lag by
                        # a frame or two; prediction keeps boxes visually glued.
                        processed = manage_frame.copy()

                        for face in face_events:
                            self._draw_face_event(processed, face)

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

                    # Keep camera identity visible in every view and snapshot.
                    camera_label = f"Camera {camera_id}"
                    if camera_name:
                        camera_label += f" - {camera_name}"
                    cv2.rectangle(processed, (8, 8), (min(w - 8, 520), 38), (0, 0, 0), -1)
                    cv2.putText(
                        processed,
                        camera_label,
                        (16, 29),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.62,
                        (255, 255, 255),
                        2,
                        cv2.LINE_AA,
                    )
                    cv2.rectangle(manage_frame, (8, 8), (min(w - 8, 520), 38), (0, 0, 0), -1)
                    cv2.putText(
                        manage_frame,
                        camera_label,
                        (16, 29),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.62,
                        (255, 255, 255),
                        2,
                        cv2.LINE_AA,
                    )

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

                    # Parse ROI polygons (now including zone_type)
                    parsed_rois = []
                    curr_h, curr_w = frame.shape[:2]
                    for roi in cached_rois:
                        try:
                            points = json.loads(roi.points)
                            pts = np.array(
                                [[int(p["x"] * curr_w), int(p["y"] * curr_h)] for p in points],
                                np.int32,
                            )
                            pts = pts.reshape((-1, 1, 2))
                            zone_type = getattr(roi, "zone_type", "observation")
                            parsed_rois.append((roi.zone_name, zone_type, pts))
                        except Exception:
                            pass
                            
                    if is_ai_active:
                        zone_signature = tuple(
                            (
                                z_name,
                                z_type,
                                tuple(tuple(point[0]) for point in pts.tolist()),
                            )
                            for z_name, z_type, pts in parsed_rois
                        )
                        now_t = time.monotonic()
                        last_zone_signature = getattr(
                            self, "_last_zone_signature", None
                        )
                        last_zone_update_at = getattr(
                            self, "_last_zone_update_at", 0.0
                        )
                        if (
                            zone_signature != last_zone_signature
                            or now_t - last_zone_update_at > 1.0
                        ):
                            vision_process_manager.update_zones(parsed_rois)
                            self._last_zone_signature = zone_signature
                            self._last_zone_update_at = now_t

                    # Helper to find zone for a bbox
                    def get_zone_for_bbox(bbox):
                        if not parsed_rois:
                            return None, "observation"
                        bc_x = (bbox[0] + bbox[2]) // 2
                        bc_y = bbox[3]
                        center_y = (bbox[1] + bbox[3]) // 2
                        for z_name, z_type, pts in parsed_rois:
                            if cv2.pointPolygonTest(pts, (bc_x, bc_y), False) >= 0 or cv2.pointPolygonTest(pts, (bc_x, center_y), False) >= 0:
                                return z_name, z_type
                        return None, "observation"

                    for ev in face_events:
                        zone_name, zone_type = get_zone_for_bbox(ev["bbox"])
                        effective_cam_name = (
                            f"{camera_name} - {zone_name}" if zone_name else camera_name
                        )

                        is_new_session = _maybe_mark_attendance(
                            ev["name"],
                            ev.get("score", 1.0),
                            camera_id=camera_id,
                            camera_name=camera_name,
                            has_mask=ev.get("has_mask", True),
                        )

                        # Zone-Based Compliance via ComplianceEngine
                        staff_name = ev["name"]
                        now_t = time.monotonic()
                        rule_throttle_key = f"{staff_name}_{effective_cam_name}"
                        last_check = last_rule_check.get(rule_throttle_key, 0)

                        zone_state = (camera_id, zone_name, zone_type)
                        previous_zone_state = self._last_staff_zone.get(staff_name)
                        if previous_zone_state != zone_state:
                            self._last_staff_zone[staff_name] = zone_state
                            if staff_name != "Unknown":
                                event_engine.publish_event(
                                    event_type="ZoneTransition",
                                    camera_id=camera_id,
                                    camera_name=effective_cam_name,
                                    confidence=ev.get("score", 0.0),
                                    details={
                                        "staff_name": staff_name,
                                        "from_camera_id": previous_zone_state[0]
                                        if previous_zone_state
                                        else None,
                                        "from_zone": previous_zone_state[1]
                                        if previous_zone_state
                                        else None,
                                        "from_zone_type": previous_zone_state[2]
                                        if previous_zone_state
                                        else None,
                                        "to_zone": zone_name,
                                        "to_zone_type": zone_type,
                                    },
                                )

                        # Only run compliance check every 2 seconds to avoid spam
                        if now_t - last_check > 2.0:
                            last_rule_check[rule_throttle_key] = now_t

                            if staff_name == "Unknown":
                                # Unknown person — apply grace period before alerting
                                from camera.vision_constants import UNKNOWN_PERSON_GRACE_PERIOD_SEC
                                
                                # Track how long this unknown person has been seen
                                unknown_duration_key = f"unknown_duration_{effective_cam_name}"
                                first_seen = last_rule_check.get(unknown_duration_key, now_t)
                                last_rule_check[unknown_duration_key] = first_seen
                                
                                if now_t - first_seen >= UNKNOWN_PERSON_GRACE_PERIOD_SEC:
                                    from camera.compliance_constants import EVENT_TYPE_UNAUTHORIZED_ENTRY
                                    event_engine.publish_event(
                                        event_type=EVENT_TYPE_UNAUTHORIZED_ENTRY,
                                        camera_id=camera_id,
                                        camera_name=effective_cam_name,
                                        confidence=ev.get("score", 0.0),
                                        details={"alert": "Unauthorized person detected."},
                                    )
                                    if not is_zone_alerted(effective_cam_name):
                                        set_zone_alert(effective_cam_name, duration_sec=10.0)
                                        from camera.audio_service import audio_service
                                        audio_service.speak(
                                            camera_url,
                                            f"Warning, unauthorized person detected on {camera_name or 'this camera'}. Please identify yourself.",
                                            vendor="tapo",
                                        )
                            else:
                                # Clear unknown duration if a known person is seen
                                unknown_duration_key = f"unknown_duration_{effective_cam_name}"
                                last_rule_check.pop(unknown_duration_key, None)

                            if zone_type == ZONE_TYPE_RESTRICTED and staff_name != "Unknown":
                                # Restricted zone: check compliance token
                                if not compliance_engine.is_verified(staff_name):
                                    missing = list(
                                        compliance_engine.get_missing_items(staff_name)
                                    )
                                    # Use current-frame PPE evidence before
                                    # speaking; a failed token can be stale.
                                    if ev.get("has_mask"):
                                        missing = [
                                            item for item in missing if item != "mask"
                                        ]
                                    if ev.get("has_left_glove"):
                                        missing = [
                                            item
                                            for item in missing
                                            if item != "left glove"
                                        ]
                                    if ev.get("has_right_glove"):
                                        missing = [
                                            item
                                            for item in missing
                                            if item != "right glove"
                                        ]
                                    if not is_zone_alerted(f"{effective_cam_name}_{staff_name}"):
                                        from camera.vision_constants import WARNING_ALERT_COOLDOWN_SEC
                                        set_zone_alert(
                                            f"{effective_cam_name}_{staff_name}",
                                            duration_sec=WARNING_ALERT_COOLDOWN_SEC,
                                        )
                                        if missing:
                                            if "mask" in missing and ev.get("has_improper_mask"):
                                                warning = f"Warning, {staff_name}, please pull your mask up to cover your nose and mouth."
                                            else:
                                                missing_text = " and ".join(missing)
                                                warning = (
                                                    f"Warning, {staff_name}, on {camera_name or 'this camera'}, please wear "
                                                    f"{missing_text}."
                                                )
                                        else:
                                            warning = (
                                                f"Warning, {staff_name}, on {camera_name or 'this camera'}, PPE verification "
                                                "is still in progress."
                                            )
                                        print(f"[Worker] 🚨 RESTRICTED ZONE VIOLATION: {staff_name} missing {missing}")
                                        event_engine.publish_event(
                                            event_type="PPEViolation",
                                            camera_id=camera_id,
                                            camera_name=effective_cam_name,
                                            confidence=ev.get("score", 0.0),
                                            details={
                                                "staff_name": staff_name,
                                                "missing_items": missing,
                                                "warning": warning,
                                            },
                                        )
                                        set_zone_alert(effective_cam_name, duration_sec=5.0)
                                        from camera.audio_service import audio_service
                                        audio_service.speak(camera_url, warning, vendor="tapo")

                    for ev in equipment_events:
                        zone_name, _ = get_zone_for_bbox(ev["bbox"])
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
                        zone_name, _ = get_zone_for_bbox(ev["bbox"])
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
                        for z_name, z_type, pts in parsed_rois:
                            effective_cam_name = f"{camera_name} - {z_name}"
                            is_alert = is_zone_alerted(effective_cam_name)
                            # Color zones by type: green=observation, yellow=verification, red=restricted
                            if is_alert:
                                fill_color = (0, 0, 255)
                            elif z_type == "restricted":
                                fill_color = (80, 80, 200)
                            elif z_type == "verification":
                                fill_color = (0, 200, 200)
                            else:
                                fill_color = (160, 200, 0)
                            cv2.fillPoly(overlay, [pts], fill_color)
                            cv2.fillPoly(manage_overlay, [pts], fill_color)

                        cv2.addWeighted(overlay, 0.25, processed, 0.75, 0, processed)
                        cv2.addWeighted(
                            manage_overlay, 0.25, manage_frame, 0.75, 0, manage_frame
                        )

                        for z_name, z_type, pts in parsed_rois:
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

            _, buf = cv2.imencode(
                ".jpg",
                processed_np,
                [cv2.IMWRITE_JPEG_QUALITY, getattr(self, "_jpeg_quality", 75)],
            )
            ai_jpeg = buf.tobytes()
        if has_ws_manage:
            import cv2

            _, buf = cv2.imencode(
                ".jpg",
                manage_frame_np,
                [cv2.IMWRITE_JPEG_QUALITY, getattr(self, "_jpeg_quality", 75)],
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
