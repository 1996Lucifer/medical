"""
Zone-Based Vision Service — Multi-Person Detection, Tracking, and PPE Workflow.

Pipeline:
    1. YOLO11n → Detect all persons in frame
    2. ByteTrack (ultralytics built-in) → Persistent track IDs across frames
    3. InsightFace → Identify each tracked person
    4. Zone Classification → Determine which zone each person is in
    5. Zone-Specific Processing:
       - Observation Zone: Track + identify only
       - Verification Zone: Run VLM PPE verification (one-shot)
       - Restricted Zone: Monitor via compliance engine lookup
"""
import cv2
import numpy as np
import os
import asyncio
import time
from typing import Dict, List, Optional, Tuple

from camera.model_manager import ModelManager, get_best_device
from camera.compliance_engine import compliance_engine

from camera.vision_constants import (
    REJECTION_THRESHOLD,
    UPPER_FACE_REJECTION_THRESHOLD,
    UPPER_FACE_HEIGHT_RATIO,
    YOLO_CONFIDENCE_THRESHOLD,
    YOLO_PERSON_CLASS,
    YOLO_CPU_IMGSZ,
    YOLO_GPU_IMGSZ,
    MIN_PERSON_ASPECT_RATIO,
    MIN_PERSON_HEIGHT_PX,
    PPE_DETECTION_CONFIDENCE_THRESHOLD,
    PPE_DETECTION_INTERVAL_FRAMES,
    PPE_EVIDENCE_TTL_FRAMES,
    PPE_REVOCATION_MISSED_SAMPLES,
    ZONE_TYPE_OBSERVATION,
    ZONE_TYPE_VERIFICATION,
    ZONE_TYPE_RESTRICTED,
    IDENTITY_REFRESH_FRAMES,
    UNKNOWN_IDENTITY_RETRY_FRAMES,
    IDENTITY_CACHE_TTL_FRAMES,
    get_runtime_vision_config,
)


class VisionServiceZones:
    """
    Zone-aware vision pipeline.
    Replaces the single-person MediaPipe Holistic approach with
    YOLO11n multi-person detection + ByteTrack tracking + InsightFace identity.
    """

    def __init__(self, camera_name: str = "Unknown Camera"):
        print("[VisionServiceZones] Initializing zone-based vision service...")
        self.camera_name = camera_name
        self.debug_zones = os.getenv("VISION_DEBUG", "0") == "1"

        # Determine optimal device and backend config
        self.device = get_best_device()
        self.runtime_config = get_runtime_vision_config()
        self.config = {
            "ctx_id": self.runtime_config["ctx_id"],
            "det_size": self.runtime_config["det_size"],
        }
        self.yolo_imgsz = (
            YOLO_CPU_IMGSZ
            if self.runtime_config["backend"] == "cpu" and self.device == "cpu"
            else YOLO_GPU_IMGSZ
        )
        print(
            f"[VisionServiceZones] Using backend: {self.runtime_config['label']} (device: '{self.device}')"
        )
        print(
            f"  det_size={self.config['det_size']}  "
            f"frame_width={self.runtime_config.get('frame_width', 640)}  "
            f"fps={self.runtime_config.get('target_fps', 15)}  "
            f"yolo_imgsz={self.yolo_imgsz}"
        )

        # Staff identity data
        self.staff_names: List[str] = []
        self.staff_ids: List[Optional[int]] = []
        self.staff_embeddings_matrix = np.empty((0, 512))
        self.staff_upper_embeddings_matrix = np.empty((0, 512))
        self.staff_has_upper_embedding = np.empty((0,), dtype=bool)

        # Tracking state
        self.identity_cache: Dict[int, dict] = {}  # track_id → {name, score, last_frame}
        self.identity_cache_ttl = IDENTITY_CACHE_TTL_FRAMES

        # VLM verification is entirely removed. We rely strictly on real-time YOLO PPE detection.

        # Zone polygon cache (set externally by the worker)
        self.zone_polygons: List[Tuple[str, str, np.ndarray]] = []
        # Each entry: (zone_name, zone_type, polygon_pts)

        # Frame counter & Human centroid tracking state
        self._frame_count = 0
        self._active_tracks: Dict[int, dict] = {}
        self._next_track_id: int = 0
        self._last_identity_run: Dict[int, int] = {}  # track_id → last frame identity was checked
        self._last_ppe_sample: Dict[int, int] = {}  # track_id → last frame PPE crops were sampled
        self._ppe_evidence: Dict[int, dict] = {}
        self._ppe_miss_streak: Dict[int, dict] = {}
        self._last_ppe_boxes: List[dict] = []


    def update_staff_embeddings(self, staff_list: list) -> None:
        """Update the staff identity database for face recognition."""
        self.staff_names = []
        self.staff_ids = []
        embeddings = []
        upper_embeddings = []
        has_upper_embeddings = []
        for staff in staff_list:
            self.staff_names.append(staff["name"])
            self.staff_ids.append(staff.get("id"))
            emb = np.asarray(staff["embedding"], dtype=np.float32)
            norm = np.linalg.norm(emb)
            if norm > 0:
                emb = emb / norm
            embeddings.append(emb)

            upper = staff.get("upper_embedding")
            upper_emb = np.zeros(512, dtype=np.float32)
            has_upper = False
            if upper is not None:
                candidate = np.asarray(upper, dtype=np.float32)
                if candidate.shape == (512,):
                    candidate_norm = np.linalg.norm(candidate)
                    if candidate_norm > 0:
                        upper_emb = candidate / candidate_norm
                        has_upper = True
            upper_embeddings.append(upper_emb)
            has_upper_embeddings.append(has_upper)

        if embeddings:
            self.staff_embeddings_matrix = np.vstack(embeddings)
            self.staff_upper_embeddings_matrix = np.vstack(upper_embeddings)
            self.staff_has_upper_embedding = np.asarray(
                has_upper_embeddings, dtype=bool
            )
        else:
            self.staff_embeddings_matrix = np.empty((0, 512))
            self.staff_upper_embeddings_matrix = np.empty((0, 512))
            self.staff_has_upper_embedding = np.empty((0,), dtype=bool)

    def update_zone_polygons(
        self, zones: List[Tuple[str, str, np.ndarray]]
    ) -> None:
        """
        Update cached zone polygons.
        Args:
            zones: list of (zone_name, zone_type, polygon_points)
        """
        self.zone_polygons = zones

    def extract_embedding(self, image_path: str) -> Optional[np.ndarray]:
        """Extract face embedding for a given image file (used for registration)."""
        app = ModelManager().get_face_analysis(self.config)
        if not app:
            return None
        frame = cv2.imread(image_path)
        if frame is None:
            return None
        faces = app.get(frame)
        if not faces:
            return None
        # Get largest face
        best_face = max(faces, key=lambda f: (f.bbox[2]-f.bbox[0])*(f.bbox[3]-f.bbox[1]))
        emb = best_face.embedding
        emb_norm = np.linalg.norm(emb)
        if emb_norm > 0:
            emb = emb / emb_norm
        return emb

    def _extract_upper_face_embedding(
        self, frame: np.ndarray, face_bbox: np.ndarray
    ) -> Optional[np.ndarray]:
        """Embed the eye and brow region for masked-face fallback matching."""
        x1, y1, x2, y2 = map(int, face_bbox)
        height, width = frame.shape[:2]
        x1, y1 = max(0, x1), max(0, y1)
        x2, y2 = min(width, x2), min(height, y2)
        face_height = y2 - y1
        if x2 <= x1 or face_height < 24:
            return None

        upper_y2 = y1 + int(face_height * UPPER_FACE_HEIGHT_RATIO)
        upper_face = frame[y1:upper_y2, x1:x2]
        if upper_face.size == 0:
            return None

        try:
            app = ModelManager().get_face_analysis(self.config)
            embedding = app.models["recognition"].get_feat(
                cv2.cvtColor(
                    cv2.resize(upper_face, (112, 112)), cv2.COLOR_BGR2RGB
                )
            ).flatten()
        except Exception as exc:
            print(f"[VisionServiceZones] Upper-face embedding failed: {exc}")
            return None

        norm = np.linalg.norm(embedding)
        return embedding / norm if norm > 0 else None

    def _classify_zone(self, bbox: list, name: str = "Unknown") -> Tuple[Optional[str], str]:
        """
        Determine which zone a person's bounding box falls into.
        Uses the bottom-center and center of the bbox as reference points.
        Returns (zone_name, zone_type). Defaults to observation if no zone matched.
        """
        if not self.zone_polygons:
            if self.debug_zones and name != "Unknown":
                print(f"[ZoneDebug] {name} at {bbox} - NO POLYGONS CONFIGURED!")
            return None, ZONE_TYPE_OBSERVATION

        bc_x = int((bbox[0] + bbox[2]) // 2)
        bc_y = int(bbox[3])  # Bottom center
        center_y = int((bbox[1] + bbox[3]) // 2) # True center

        for zone_name, zone_type, pts in self.zone_polygons:
            if cv2.pointPolygonTest(pts, (bc_x, bc_y), False) >= 0 or cv2.pointPolygonTest(pts, (bc_x, center_y), False) >= 0:
                if self.debug_zones and name != "Unknown":
                    print(f"[ZoneDebug] {name} at {bbox} IN ZONE: {zone_name} ({zone_type})")
                return zone_name, zone_type

        return None, ZONE_TYPE_OBSERVATION

    def _update_human_tracks(self, current_detections: List[dict]) -> List[dict]:
        """
        Maintain persistent human track IDs across consecutive frames using centroid matching.
        """
        updated_tracks = []
        for det in current_detections:
            x1, y1, x2, y2 = det["bbox"]
            cx, cy = (x1 + x2) / 2.0, (y1 + y2) / 2.0

            best_tid = -1
            min_dist = 220.0  # Max pixel distance for same track across frames
            for tid, t_data in self._active_tracks.items():
                tcx, tcy = t_data["centroid"]
                dist = ((cx - tcx)**2 + (cy - tcy)**2)**0.5
                if dist < min_dist:
                    min_dist = dist
                    best_tid = tid

            if best_tid == -1:
                self._next_track_id += 1
                best_tid = self._next_track_id

            self._active_tracks[best_tid] = {
                "centroid": (cx, cy),
                "bbox": det["bbox"],
                "last_frame": self._frame_count,
            }
            item = det.copy()
            item["track_id"] = best_tid
            updated_tracks.append(item)

        # Prune inactive tracks older than 60 frames
        stale_tids = [
            tid for tid, t_data in self._active_tracks.items()
            if self._frame_count - t_data["last_frame"] > 60
        ]
        for tid in stale_tids:
            del self._active_tracks[tid]

        return updated_tracks

    @staticmethod
    def _is_plausible_person_bbox(bbox: list) -> bool:
        """Filter geometrically impossible person detections before tracking/alerts."""
        x1, y1, x2, y2 = bbox
        width = max(0, x2 - x1)
        height = max(0, y2 - y1)
        if height < MIN_PERSON_HEIGHT_PX or width <= 0:
            return False
        aspect_ratio = width / height
        return aspect_ratio >= MIN_PERSON_ASPECT_RATIO

    def _identify_person(
        self, frame: np.ndarray, bbox: list, track_id: int
    ) -> Tuple[str, float, Optional[int]]:
        """
        Run InsightFace on the person's bounding box region to identify them.
        Uses caching to avoid running InsightFace every frame.
        """
        # Check cache first
        cached = self.identity_cache.get(track_id)
        if cached:
            frames_since = self._frame_count - cached.get("last_frame", 0)
            if (
                cached["name"] != "Unknown"
                and frames_since < self.identity_cache_ttl
            ):
                return cached["name"], cached["score"], cached.get("staff_id")

        # Run InsightFace
        app = ModelManager().get_face_analysis(self.config)
        if not app:
            return "Unknown", 0.0, None

        # Crop the person region with margin for face detection
        h, w = frame.shape[:2]
        x1, y1, x2, y2 = map(int, bbox)
        margin = int((x2 - x1) * 0.2)
        rx1 = max(0, x1 - margin)
        ry1 = max(0, y1 - margin)
        rx2 = min(w, x2 + margin)
        ry2 = min(h, y2 + margin)
        person_crop = frame[ry1:ry2, rx1:rx2]

        if person_crop.size == 0:
            return "Unknown", 0.0, None

        faces = app.get(person_crop)
        if not faces:
            return "Unknown", 0.0, None

        # Pick the largest face in the crop
        best_face = max(faces, key=lambda f: (f.bbox[2] - f.bbox[0]) * (f.bbox[3] - f.bbox[1]))
        emb = best_face.embedding
        emb_norm = np.linalg.norm(emb)
        if emb_norm > 0:
            emb = emb / emb_norm

        if self.staff_embeddings_matrix.shape[0] == 0:
            return "Unknown", 0.0, None

        scores = np.dot(self.staff_embeddings_matrix, emb)
        best_idx = int(np.argmax(scores))
        best_score = float(scores[best_idx])
        name = "Unknown"
        staff_id = None
        identity_source = "full_face"

        if best_score >= REJECTION_THRESHOLD:
            name = self.staff_names[best_idx]
            staff_id = self.staff_ids[best_idx]
        elif self.staff_has_upper_embedding.any():
            upper_emb = self._extract_upper_face_embedding(
                person_crop, best_face.bbox
            )
            if upper_emb is not None:
                upper_scores = np.dot(self.staff_upper_embeddings_matrix, upper_emb)
                upper_scores[~self.staff_has_upper_embedding] = -1.0
                upper_best_idx = int(np.argmax(upper_scores))
                upper_best_score = float(upper_scores[upper_best_idx])
                if upper_best_score >= UPPER_FACE_REJECTION_THRESHOLD:
                    name = self.staff_names[upper_best_idx]
                    staff_id = self.staff_ids[upper_best_idx]
                    best_score = upper_best_score
                    identity_source = "upper_face"

        # Cache the result
        self.identity_cache[track_id] = {
            "name": name,
            "staff_id": staff_id,
            "score": best_score,
            "identity_source": identity_source,
            "last_frame": self._frame_count,
            "last_bbox": bbox,
            "face_bbox": [
                rx1 + int(best_face.bbox[0]),
                ry1 + int(best_face.bbox[1]),
                rx1 + int(best_face.bbox[2]),
                ry1 + int(best_face.bbox[3]),
            ],
        }
        self._last_identity_run[track_id] = self._frame_count

        return name, best_score, staff_id

    def _crop_face_region(
        self,
        frame: np.ndarray,
        person_bbox: list,
        detected_face_bbox: Optional[list] = None,
    ) -> Optional[np.ndarray]:
        """
        Use MediaPipe Face Mesh to locate and crop the face region
        within a person's bounding box.
        """
        if detected_face_bbox is not None:
            h, w = frame.shape[:2]
            x1, y1, x2, y2 = map(int, detected_face_bbox)
            x1, y1 = max(0, x1), max(0, y1)
            x2, y2 = min(w, x2), min(h, y2)
            crop = frame[y1:y2, x1:x2]
            if crop.size > 0:
                return crop

        face_mesh = ModelManager().get_mp_face_mesh()
        if not face_mesh:
            # Fallback: use top 40% of person bbox as face estimate
            x1, y1, x2, y2 = map(int, person_bbox)
            face_h = int((y2 - y1) * 0.4)
            crop = frame[y1 : y1 + face_h, x1:x2]
            return crop if crop.size > 0 else None

        h, w = frame.shape[:2]
        x1, y1, x2, y2 = map(int, person_bbox)
        margin_x = int((x2 - x1) * 0.1)
        margin_y = int((y2 - y1) * 0.1)
        px1 = max(0, x1 - margin_x)
        py1 = max(0, y1 - margin_y)
        px2 = min(w, x2 + margin_x)
        py2 = min(h, y2 + margin_y)

        person_crop = frame[py1:py2, px1:px2]
        if person_crop.size == 0:
            return None

        rgb = cv2.cvtColor(person_crop, cv2.COLOR_BGR2RGB)
        results = face_mesh.process(rgb)

        if not results.multi_face_landmarks:
            # Fallback: top 40%
            face_h = int((py2 - py1) * 0.4)
            return person_crop[:face_h, :]

        landmarks = results.multi_face_landmarks[0]
        ph, pw = person_crop.shape[:2]
        xs = [int(lm.x * pw) for lm in landmarks.landmark]
        ys = [int(lm.y * ph) for lm in landmarks.landmark]

        fx1 = max(0, min(xs) - 10)
        fy1 = max(0, min(ys) - 10)
        fx2 = min(pw, max(xs) + 10)
        fy2 = min(ph, max(ys) + 10)

        face_crop = person_crop[fy1:fy2, fx1:fx2]
        return face_crop if face_crop.size > 0 else None

    def _crop_hand_regions(
        self, frame: np.ndarray, person_bbox: list
    ) -> Tuple[Optional[np.ndarray], Optional[np.ndarray]]:
        """
        Use MediaPipe Hands to locate and crop left and right hand regions.
        Returns (left_hand_crop, right_hand_crop).
        """
        hands = ModelManager().get_mp_hands()

        h, w = frame.shape[:2]
        x1, y1, x2, y2 = map(int, person_bbox)
        margin_x = int((x2 - x1) * 0.15)
        margin_y = int((y2 - y1) * 0.15)
        px1 = max(0, x1 - margin_x)
        py1 = max(0, y1 - margin_y)
        px2 = min(w, x2 + margin_x)
        py2 = min(h, y2 + margin_y)

        person_crop = frame[py1:py2, px1:px2]
        if person_crop.size == 0:
            return None, None

        if not hands:
            # Fallback: lower 50%, split left and right
            ph, pw = person_crop.shape[:2]
            mid_y = int(ph * 0.5)
            mid_x = int(pw * 0.5)
            left_crop = person_crop[mid_y:, mid_x:]
            right_crop = person_crop[mid_y:, :mid_x]
            return left_crop, right_crop

        rgb = cv2.cvtColor(person_crop, cv2.COLOR_BGR2RGB)
        results = hands.process(rgb)

        if not results.multi_hand_landmarks or not results.multi_handedness:
            # Fallback: lower 50%, split left and right
            ph, pw = person_crop.shape[:2]
            mid_y = int(ph * 0.5)
            mid_x = int(pw * 0.5)
            # Image right side = Person's left hand
            left_crop = person_crop[mid_y:, mid_x:]
            # Image left side = Person's right hand
            right_crop = person_crop[mid_y:, :mid_x]
            return left_crop, right_crop

        ph, pw = person_crop.shape[:2]
        left_crop = None
        right_crop = None

        for hand_lm, handedness in zip(
            results.multi_hand_landmarks, results.multi_handedness
        ):
            # MediaPipe reports handedness from camera perspective (mirrored)
            label = handedness.classification[0].label  # "Left" or "Right"

            pts = np.array(
                [
                    [int(lm.x * pw), int(lm.y * ph)]
                    for lm in hand_lm.landmark
                ],
                dtype=np.int32,
            )
            hx1 = max(0, np.min(pts[:, 0]) - 15)
            hy1 = max(0, np.min(pts[:, 1]) - 15)
            hx2 = min(pw, np.max(pts[:, 0]) + 15)
            hy2 = min(ph, np.max(pts[:, 1]) + 15)

            crop = person_crop[hy1:hy2, hx1:hx2]
            if crop.size == 0:
                continue

            # Note: MediaPipe "Right" from camera = person's left hand
            if label == "Right":
                left_crop = crop
            else:
                right_crop = crop

        return left_crop, right_crop

    def _get_texture_variance(self, image_bgr: np.ndarray, bbox: List[int]) -> float:
        """
        Calculate Laplacian variance of a bounding box.
        High variance = lots of detail (bare face: lips, nose, pores).
        Low variance = smooth surface (medical mask).
        """
        x1, y1, x2, y2 = bbox
        # Add a tiny bit of padding to avoid edges
        pad = 2
        x1, y1 = max(0, x1 + pad), max(0, y1 + pad)
        x2, y2 = max(0, x2 - pad), max(0, y2 - pad)
        crop = image_bgr[y1:y2, x1:x2]
        if crop.size == 0:
            return 0.0
        gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
        laplacian = cv2.Laplacian(gray, cv2.CV_64F)
        return float(np.var(laplacian))

    def _detect_ppe_for_tracks(
        self, frame: np.ndarray, tracked_people: List[Tuple[int, list]]
    ) -> Dict[int, dict]:
        """Associate mask and glove detections with the current person tracks."""
        if self._frame_count % PPE_DETECTION_INTERVAL_FRAMES != 0:
            return self._current_ppe_evidence(tracked_people)

        detector = ModelManager().get_ppe_detector()
        if detector is None:
            return self._current_ppe_evidence(tracked_people)

        current = {
            track_id: {"mask": False, "left_glove": False, "right_glove": False}
            for track_id, _ in tracked_people
        }
        try:
            # best.fp16.onnx has static ONNX input shape of 640x640
            ppe_imgsz = 640
            results = detector(
                frame,
                conf=PPE_DETECTION_CONFIDENCE_THRESHOLD,
                imgsz=ppe_imgsz,
                device=self.device,
                verbose=False,
            )
            boxes = results[0].boxes if results else None
            if boxes is None:
                # A completed detector pass with no PPE boxes is a genuine
                # negative sample for the visible track.
                for track_id, _ in tracked_people:
                    miss_streak = self._ppe_miss_streak.setdefault(track_id, {})
                    for item in ("mask", "left_glove", "right_glove"):
                        miss_streak[item] = miss_streak.get(item, 0) + 1
                evidence_by_track = self._current_ppe_evidence(tracked_people)
                for track_id, evidence in evidence_by_track.items():
                    streak = self._ppe_miss_streak.get(track_id, {})
                    for item in ("mask", "left_glove", "right_glove"):
                        evidence[f"negative_{item}"] = (
                            streak.get(item, 0) >= PPE_REVOCATION_MISSED_SAMPLES
                        )
                return evidence_by_track

            # ONNX export loses class names and generates class0-class999.
            # Force the correct PPE mapping.
            names = {
                0: "person",
                1: "mask",
                2: "face_shield",
                3: "gloves",
                4: "gown",
                5: "goggles",
            }
            self._last_ppe_boxes = []
            for detection in boxes:
                cls_id = int(detection.cls[0])
                conf = float(detection.conf[0])

                raw_label = str(names.get(cls_id, f"cls_{cls_id}")).lower()
                if raw_label in ("glove", "gloves"):
                    label = "glove"
                elif raw_label in ("mask", "masks"):
                    label = "mask"
                else:
                    label = raw_label

                x1, y1, x2, y2 = detection.xyxy[0].cpu().numpy().astype(int)

                box_dict = None
                if label != "person":
                    box_dict = {
                        "class": label,
                        "score": conf,
                        "bbox": [int(x1), int(y1), int(x2), int(y2)],
                    }
                    self._last_ppe_boxes.append(box_dict)

                if label not in ("mask", "glove"):
                    continue
                
                for track_id, person_bbox in tracked_people:
                    px1, py1, px2, py2 = person_bbox
                    width = max(1, px2 - px1)
                    height = max(1, py2 - py1)
                    center_x, center_y = (x1 + x2) / 2, (y1 + y2) / 2
                    if not (
                        px1 - width * 0.25 <= center_x <= px2 + width * 0.25
                        and py1 - height * 0.10 <= center_y <= py2 + height * 0.10
                    ):
                        continue
                    if label == "mask":
                        is_properly_worn = False
                        cached_identity = self.identity_cache.get(track_id, {})
                        face_bbox = cached_identity.get("face_bbox")
                        last_bbox = cached_identity.get("last_bbox")

                        if face_bbox and last_bbox:
                            # Shift face_bbox by person's movement since caching
                            lx1, ly1, lx2, ly2 = last_bbox
                            dx, dy = px1 - lx1, py1 - ly1
                            
                            s_fy1 = face_bbox[1] + dy
                            s_fy2 = face_bbox[3] + dy
                            face_height = max(1, s_fy2 - s_fy1)
                            
                            # Top of mask (y1) must be above the nose area (approx 65% down the face)
                            is_proper_top = y1 <= s_fy1 + face_height * 0.65
                            
                            # Center of mask must be above the bottom of the chin
                            is_proper_center = center_y <= s_fy2
                            
                            is_properly_worn = is_proper_top and is_proper_center
                        else:
                            # Fallback geometric heuristic if face not yet detected by InsightFace
                            # Extremely strict threshold: mask center must be in top 30% of body box
                            is_properly_worn = center_y <= py1 + height * 0.30

                        is_bare_face = False
                        if is_properly_worn:
                            tex_var = self._get_texture_variance(frame, [x1, y1, x2, y2])
                            # If texture detail is high, it's bare skin (lips, nose), not a mask
                            if tex_var > 65.0:
                                is_properly_worn = False
                                is_bare_face = True

                        if is_properly_worn:
                            current[track_id]["mask"] = True
                        elif not is_bare_face:
                            current[track_id]["improper_mask"] = True
                            if box_dict is not None:
                                box_dict["class"] = "mask (improper)"
                        elif box_dict is not None:
                            box_dict["class"] = "mask (false positive)"
                    elif label == "glove":
                        side = "left_glove" if center_x >= (px1 + px2) / 2 else "right_glove"
                        current[track_id][side] = True

            for track_id, _ in tracked_people:
                evidence = current.get(track_id, {})
                cached = self._ppe_evidence.setdefault(track_id, {})
                miss_streak = self._ppe_miss_streak.setdefault(track_id, {})
                
                for item in ["mask", "left_glove", "right_glove"]:
                    if evidence.get(item, False):
                        cached[f"{item}_frame"] = self._frame_count
                        miss_streak[item] = 0
                    else:
                        miss_streak[item] = miss_streak.get(item, 0) + 1
                        
                # improper_mask doesn't need a miss streak for revocation, but we cache the frame
                if evidence.get("improper_mask", False):
                    cached["improper_mask_frame"] = self._frame_count
        except Exception as exc:
            print(f"[VisionServiceZones] PPE detector error: {exc}")

        evidence_by_track = self._current_ppe_evidence(tracked_people)
        for track_id, evidence in evidence_by_track.items():
            streak = self._ppe_miss_streak.get(track_id, {})
            evidence["negative_mask"] = (
                streak.get("mask", 0) >= PPE_REVOCATION_MISSED_SAMPLES
            )
            evidence["negative_left_glove"] = (
                streak.get("left_glove", 0) >= PPE_REVOCATION_MISSED_SAMPLES
            )
            evidence["negative_right_glove"] = (
                streak.get("right_glove", 0) >= PPE_REVOCATION_MISSED_SAMPLES
            )
        return evidence_by_track

    def _current_ppe_evidence(
        self, tracked_people: List[Tuple[int, list]]
    ) -> Dict[int, dict]:
        """Return recent positive PPE evidence without treating a miss as absence."""
        evidence_by_track = {}
        for track_id, _ in tracked_people:
            cached = self._ppe_evidence.get(track_id, {})
            evidence_by_track[track_id] = {
                "mask": self._frame_count - cached.get("mask_frame", -9999)
                <= PPE_EVIDENCE_TTL_FRAMES,
                "improper_mask": self._frame_count - cached.get("improper_mask_frame", -9999)
                <= PPE_EVIDENCE_TTL_FRAMES,
                "left_glove": self._frame_count
                - cached.get("left_glove_frame", -9999)
                <= PPE_EVIDENCE_TTL_FRAMES,
                "right_glove": self._frame_count
                - cached.get("right_glove_frame", -9999)
                <= PPE_EVIDENCE_TTL_FRAMES,
            }
        return evidence_by_track

    def process_frame(
        self, frame: np.ndarray, camera_id: Optional[int] = None
    ) -> Tuple[np.ndarray, list, list, list, list]:
        """
        Main processing pipeline for a single frame.

        Returns:
            (annotated_frame, face_events, equipment_events, incident_events, ppe_events)
        """
        self._frame_count += 1
        original_frame = frame.copy()
        fh, fw = frame.shape[:2]

        face_events = []
        equipment_events = []
        incident_events = []
        ppe_events = []

        # ── Step 1: Detect Human Faces & Landmarks (InsightFace SCRFD) ──────
        app = ModelManager().get_face_analysis(self.config)
        if not app:
            return frame, face_events, equipment_events, incident_events, ppe_events

        faces = app.get(original_frame)
        if not faces or len(faces) == 0:
            return frame, face_events, equipment_events, incident_events, ppe_events

        current_detections = []
        for face in faces:
            det_conf = float(getattr(face, "det_score", 0.90))
            # InsightFace SCRFD can hallucinate faces in clothes/books at lower confidences
            if det_conf < 0.65:
                continue

            fx1, fy1, fx2, fy2 = map(int, face.bbox)
            fw_box = max(1, fx2 - fx1)
            fh_box = max(1, fy2 - fy1)

            # Extrapolate full person body bounds from facial landmark proportions
            px1 = max(0, fx1 - int(fw_box * 0.8))
            py1 = max(0, fy1 - int(fh_box * 0.3))
            px2 = min(fw, fx2 + int(fw_box * 0.8))
            py2 = min(fh, fy2 + int(fh_box * 4.5))
            person_bbox = [px1, py1, px2, py2]

            emb = face.embedding
            emb_norm = np.linalg.norm(emb)
            if emb_norm > 0:
                emb = emb / emb_norm

            name = "Unknown"
            score = 0.0
            staff_id = None

            if self.staff_embeddings_matrix.shape[0] > 0 and emb is not None:
                scores = np.dot(self.staff_embeddings_matrix, emb)
                best_idx = int(np.argmax(scores))
                best_score = float(scores[best_idx])
                if best_score >= REJECTION_THRESHOLD:
                    name = self.staff_names[best_idx]
                    staff_id = self.staff_ids[best_idx]
                    score = best_score
                elif self.staff_has_upper_embedding.any():
                    upper_emb = self._extract_upper_face_embedding(original_frame, face.bbox)
                    if upper_emb is not None:
                        upper_scores = np.dot(self.staff_upper_embeddings_matrix, upper_emb)
                        upper_scores[~self.staff_has_upper_embedding] = -1.0
                        upper_best_idx = int(np.argmax(upper_scores))
                        upper_best_score = float(upper_scores[upper_best_idx])
                        if upper_best_score >= UPPER_FACE_REJECTION_THRESHOLD:
                            name = self.staff_names[upper_best_idx]
                            staff_id = self.staff_ids[upper_best_idx]
                            score = upper_best_score

            current_detections.append({
                "face_bbox": [fx1, fy1, fx2, fy2],
                "bbox": person_bbox,
                "name": name,
                "score": score,
                "staff_id": staff_id,
                "det_conf": float(getattr(face, "det_score", 0.90)),
            })

        tracked_human_objects = self._update_human_tracks(current_detections)
        if not tracked_human_objects:
            return frame, face_events, equipment_events, incident_events, ppe_events

        tracked_people = [(det["track_id"], det["bbox"]) for det in tracked_human_objects]
        ppe_by_track = self._detect_ppe_for_tracks(original_frame, tracked_people)

        # ── Step 2: Process Each Tracked Person ───────────────────────────
        active_track_ids = set()
        
        for det in tracked_human_objects:
            bbox = det["bbox"]
            track_id = det["track_id"]
            det_conf = det["det_conf"]
            name = det["name"]
            score = det["score"]
            staff_id = det["staff_id"]
            active_track_ids.add(track_id)

            # ── Step 4: Zone Classification ───────────────────────────────────
            zone_name, zone_type = self._classify_zone(bbox, name)

            # ── Step 5: Zone-Specific Processing ──────────────────────────
            token = compliance_engine.get_token(name) if name != "Unknown" else None
            is_verified = bool(token and compliance_engine.is_verified(name))
            observed_ppe = ppe_by_track.get(
                track_id,
                {
                    "mask": False,
                    "left_glove": False,
                    "right_glove": False,
                    "negative_mask": False,
                    "negative_left_glove": False,
                    "negative_right_glove": False,
                },
            )

            # A verified token is conditional on PPE remaining present. Revoke
            # only after several consecutive detector samples to tolerate blur
            # or a momentary occlusion.
            if token and is_verified and zone_type == ZONE_TYPE_RESTRICTED:
                revoked_items = []
                if observed_ppe.get("negative_mask"):
                    revoked_items.append("mask")
                if observed_ppe.get("negative_left_glove"):
                    revoked_items.append("left glove")
                if observed_ppe.get("negative_right_glove"):
                    revoked_items.append("right glove")
                if revoked_items:
                    reason = f"removed: {', '.join(revoked_items)}"
                    compliance_engine.revoke(
                        name, reason=reason, missing_items=revoked_items
                    )
                    token = None
                    is_verified = False

            if zone_type in (ZONE_TYPE_VERIFICATION, ZONE_TYPE_RESTRICTED):
                # We now verify compliance LIVE on every frame using the real-time PPE YOLO boxes.
                if name != "Unknown" and not is_verified:
                    has_m = observed_ppe.get("mask", False)
                    has_l = observed_ppe.get("left_glove", False)
                    has_r = observed_ppe.get("right_glove", False)
                    
                    if has_m and has_l and has_r:
                        compliance_engine.record_verification(
                            staff_name=name,
                            has_mask=has_m,
                            has_left_glove=has_l,
                            has_right_glove=has_r,
                            camera_id=camera_id,
                            confidence=0.8,
                        )
                        is_verified = True
                        token = compliance_engine.get_token(name)
                        
            if zone_type == ZONE_TYPE_RESTRICTED:
                # In restricted zone: check if verified, alert if not
                if name != "Unknown" and not is_verified:
                    ppe_events.append(
                        {
                            "type": "unauthorized_entry",
                            "name": name,
                            "bbox": bbox,
                            "zone": zone_name,
                            "missing": compliance_engine.get_missing_items(name),
                        }
                    )

            # ── Step 6: Draw Annotations ──────────────────────────────────
            self._draw_person(
                frame,
                bbox,
                track_id,
                name,
                staff_id,
                score,
                zone_name,
                zone_type,
                is_verified,
                det_conf,
                observed_ppe=observed_ppe,
            )

            # ── Build face event (compatibility with existing worker) ─────
            face_events.append(
                {
                    "tid": track_id,
                    "name": name,
                    "score": score,
                    "bbox": bbox,
                    "has_mask": bool(observed_ppe.get("mask", False)),
                    "has_improper_mask": bool(observed_ppe.get("improper_mask", False)),
                    "has_left_glove": bool(observed_ppe.get("left_glove", False)),
                    "has_right_glove": bool(observed_ppe.get("right_glove", False)),
                    "has_gloves": bool(
                        observed_ppe.get("left_glove", False)
                        or observed_ppe.get("right_glove", False)
                    ),
                    "zone_name": zone_name,
                    "zone_type": zone_type,
                    "is_verified": is_verified,
                    "kps": None,
                }
            )

        # ── Cleanup stale identity cache entries ──────────────────────────
        stale_ids = [
            tid
            for tid in self.identity_cache
            if tid not in active_track_ids
            and (self._frame_count - self.identity_cache[tid].get("last_frame", 0))
            > self.identity_cache_ttl * 2
        ]
        for tid in stale_ids:
            del self.identity_cache[tid]
            self._last_identity_run.pop(tid, None)
            self._last_ppe_sample.pop(tid, None)

        for tid in list(self._ppe_evidence):
            if tid not in active_track_ids:
                del self._ppe_evidence[tid]

        # Append raw PPE bounding boxes to events so the worker can draw them
        ppe_events.extend(self._last_ppe_boxes)

        return frame, face_events, equipment_events, incident_events, ppe_events

    # _schedule_vlm_verification and verification_session_manager were removed.
    def _draw_person(
        self,
        frame: np.ndarray,
        bbox: list,
        track_id: int,
        name: str,
        staff_id: Optional[int],
        score: float,
        zone_name: Optional[str],
        zone_type: str,
        is_verified: bool,
        det_conf: float,
        observed_ppe: Optional[dict] = None,
    ) -> None:
        """Draw person bounding box with zone-aware coloring and PPE status."""
        x1, y1, x2, y2 = bbox
        token = compliance_engine.get_token(name) if name != "Unknown" else None
        obs = observed_ppe or {}

        has_mask = bool(obs.get("mask", False))
        has_left = bool(obs.get("left_glove", False))
        has_right = bool(obs.get("right_glove", False))
        has_gloves = bool(has_left or has_right)

        def get_ppe_status_text() -> str:
            m_text = "MASK ✓" if has_mask else "NO MASK ❌"
            g_text = "GLOVES ✓" if has_gloves else "NO GLOVES ❌"
            return f"{m_text} | {g_text}"

        # Color coding based on zone + status
        if name == "Unknown":
            color = (0, 0, 255)  # Red for unknown
            status = f"UNAUTHORIZED ({get_ppe_status_text()})"
        elif zone_type == ZONE_TYPE_RESTRICTED:
            if is_verified or (has_mask and has_gloves):
                color = (0, 255, 0)  # Green for verified in restricted
                status = f"VERIFIED ✓ ({get_ppe_status_text()})"
            else:
                color = (0, 0, 255)  # Red for unverified in restricted
                status = f"RESTRICTED VIOLATION 🚨 ({get_ppe_status_text()})"
        elif zone_type == ZONE_TYPE_VERIFICATION:
            if is_verified or (has_mask and has_gloves):
                color = (0, 255, 0)  # Green
                status = f"VERIFIED ✓ ({get_ppe_status_text()})"
            else:
                color = (0, 165, 255)  # Orange for pending
                status = f"VERIFYING... ({get_ppe_status_text()})"
        else:
            # Observation zone
            if not has_mask or not has_gloves:
                color = (0, 165, 255) if (has_mask or has_gloves) else (0, 0, 255)  # Orange / Red
            else:
                color = (0, 255, 0)  # Green for known with PPE
            status = get_ppe_status_text()

        # Draw bounding box
        cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)

        # Draw label
        if staff_id is not None:
            label = f"#{staff_id} {name}"
        else:
            label = f"{name}"
        if score > 0:
            label += f" {score:.0%}"
        cv2.putText(
            frame,
            label,
            (x1, max(15, y1 - 10)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            color,
            1,
        )

        # Draw status below bbox
        if status:
            cv2.putText(
                frame,
                status,
                (x1, min(frame.shape[0] - 5, y2 + 20)),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.55,
                color,
                2,
            )

        # Draw zone label at top-right of bbox
        if zone_name:
            zone_label = f"[{zone_name}]"
            cv2.putText(
                frame,
                zone_label,
                (max(0, x2 - 100), max(0, y1 - 10)),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.4,
                (200, 200, 200),
                1,
            )


# Module-level singleton
vision_service = VisionServiceZones()
