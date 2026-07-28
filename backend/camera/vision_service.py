import cv2
import numpy as np
import onnxruntime as ort
import json
import os
import onnxruntime as ort
from camera.model_manager import ModelManager

from camera.constants.vision_constants import (
    REJECTION_THRESHOLD,
    MIN_FACE_SIZE,
    get_runtime_vision_config,
)

def detect_compute_backend() -> dict:
    """
    Detect the best available compute backend and return
    quality settings tuned for that backend.
    """
    return get_runtime_vision_config(ort.get_available_providers())



class VisionService:
    def __init__(self):
        self.config = detect_compute_backend()
        print(f"[VisionService] Using backend: {self.config['label']}")
        print(f"  det_size={self.config['det_size']}  "
              f"frame_width={self.config['frame_width']}  "
              f"fps={self.config['target_fps']}")

        self.rejection_threshold = REJECTION_THRESHOLD
        self.min_face_size = MIN_FACE_SIZE

        self.staff_names = []
        self.staff_embeddings_matrix = np.empty((0, 512))
        self.staff_upper_embeddings_matrix = np.empty((0, 512))
        
        self.active_face_tracks = {}
        self.next_track_id = 0
        self.identity_cache = {}
        
        self.ppe_config_path = os.path.join(os.path.dirname(__file__), "..", "config", "ppe_colors.json")

    def _hex_to_hsv_mask(self, hex_code: str, h_tol: int, s_tol: int, v_tol: int, hsv_frame: np.ndarray):
        hex_code = hex_code.lstrip('#')
        rgb = tuple(int(hex_code[i:i+2], 16) for i in (0, 2, 4))
        color_bgr = np.uint8([[[rgb[2], rgb[1], rgb[0]]]])
        color_hsv = cv2.cvtColor(color_bgr, cv2.COLOR_BGR2HSV)[0][0]
        h, s, v = int(color_hsv[0]), int(color_hsv[1]), int(color_hsv[2])
        lower_bound = np.array([max(0, h - h_tol), max(0, s - s_tol), max(0, v - v_tol)])
        upper_bound = np.array([min(179, h + h_tol), min(255, s + s_tol), min(255, v + v_tol)])
        return cv2.inRange(hsv_frame, lower_bound, upper_bound)
        
    def _get_dynamic_color_mask(self, hsv_frame: np.ndarray):
        combined_mask = np.zeros(hsv_frame.shape[:2], dtype=np.uint8)
        if not os.path.exists(self.ppe_config_path):
            return combined_mask
            
        try:
            with open(self.ppe_config_path, 'r') as f:
                config = json.load(f)
            
            for color in config.get("ppe_colors", []):
                if not color.get("enabled", False):
                    continue
                mask = self._hex_to_hsv_mask(
                    color["hex"], 
                    color.get("hue_tolerance", 20),
                    color.get("sat_tolerance", 50),
                    color.get("val_tolerance", 50),
                    hsv_frame
                )
                combined_mask = cv2.bitwise_or(combined_mask, mask)
        except Exception as e:
            print(f"[VisionService] Error reading PPE config: {e}")
            
        return combined_mask

    def update_staff_embeddings(self, staff_list):
        self.staff_names = []
        embeddings = []
        upper_embeddings = []
        for staff in staff_list:
            self.staff_names.append(staff["name"])
            
            emb = np.array(staff["embedding"])
            norm = np.linalg.norm(emb)
            if norm > 0:
                emb = emb / norm
            embeddings.append(emb)
            
            upper = staff.get("upper_embedding")
            if upper is not None:
                u_emb = np.array(upper)
                u_norm = np.linalg.norm(u_emb)
                if u_norm > 0:
                    u_emb = u_emb / u_norm
            else:
                u_emb = np.zeros(512)
            upper_embeddings.append(u_emb)
            
        if embeddings:
            self.staff_embeddings_matrix = np.vstack(embeddings)
            self.staff_upper_embeddings_matrix = np.vstack(upper_embeddings)
        else:
            self.staff_embeddings_matrix = np.empty((0, 512))
            self.staff_upper_embeddings_matrix = np.empty((0, 512))
        print(f"[VisionService] Cached {len(embeddings)} face embeddings in memory.")

    # ── Properties consumed by routes.py ─────────────────────────────────────

    @property
    def frame_width(self) -> int:
        return self.config["frame_width"]

    @property
    def jpeg_quality(self) -> int:
        return self.config["jpeg_quality"]

    @property
    def target_fps(self) -> int:
        return self.config["target_fps"]

    @property
    def backend_label(self) -> str:
        return self.config["label"]

    # ── Core methods ──────────────────────────────────────────────────────────

    def extract_embedding(self, image_path: str):
        """
        Reads an image from disk and extracts the 512D face embedding.
        Returns the embedding as a numpy array, or None if no face found.
        """
        img = cv2.imread(image_path)
        if img is None:
            return None
        app = ModelManager().get_face_analysis(self.config)
        faces = app.get(img)
        if not faces:
            return None
        return faces[0].embedding

    def extract_upper_embedding(self, image_path: str = None, img: np.ndarray = None, bbox: list = None):
        """
        Mimics Apple's mask algorithm by cropping the upper 45% of the face
        (periocular region: eyes/eyebrows) and generating a dedicated 512D embedding.
        """
        if img is None and image_path:
            img = cv2.imread(image_path)
        if img is None:
            return None
            
        if bbox is None:
            app = ModelManager().get_face_analysis(self.config)
            faces = app.get(img)
            if not faces:
                return None
            bbox = faces[0].bbox.astype(int)
            
        # Crop the face bounding box
        x1, y1, x2, y2 = map(int, bbox)
        h, w, _ = img.shape
        x1, y1 = max(0, x1), max(0, y1)
        x2, y2 = min(w, x2), min(h, y2)
        
        face_h = y2 - y1
        face_w = x2 - x1
        if face_h <= 0 or face_w <= 0:
            return None
            
        # Crop the upper 45% of the face
        upper_h = int(face_h * 0.45)
        upper_face_crop = img[y1 : y1 + upper_h, x1 : x2]
        
        if upper_face_crop.size == 0:
            return None
            
        # InsightFace's recognition model expects a 112x112 RGB image
        upper_face_resized = cv2.resize(upper_face_crop, (112, 112))
        upper_face_rgb = cv2.cvtColor(upper_face_resized, cv2.COLOR_BGR2RGB)
        
        # Directly pass the cropped unaligned upper face to the ArcFace recognition model
        app = ModelManager().get_face_analysis(self.config)
        embedding = app.models['recognition'].get_feat(upper_face_rgb)
        return embedding.flatten()

    def cosine_similarity(self, embedding1, embedding2):
        dot = np.dot(embedding1, embedding2)
        n1 = np.linalg.norm(embedding1)
        n2 = np.linalg.norm(embedding2)
        return dot / (n1 * n2) if (n1 and n2) else 0.0

    def process_frame(self, frame):
        """
        Optimized Shared Pipeline:
        1. Equipment (Beds)
        2. Primary Person Detection (YOLO-Pose)
        3. Only if people present: Face Recognition & PPE
        4. Incidents (Falls/Theft)
        Returns:
            (processed_frame, face_events, equipment_events, incident_events)
        """
        face_events = []
        equipment_events = []
        incident_events = []
        ppe_events = []

        # 1. Equipment Tracking
        yolo_equipment = ModelManager().get_yolo_equipment()
        if yolo_equipment:
            results = yolo_equipment.track(frame, persist=True, verbose=False)
            if results and results[0].boxes:
                boxes = results[0].boxes
                for box in boxes:
                    cls_id = int(box.cls[0])
                    if cls_id in [59]:
                        conf = float(box.conf[0])
                        track_id = int(box.id[0]) if box.id is not None else -1
                        label_map = {59: "Bed"}
                        equip_class = label_map.get(cls_id, "Equipment")
                        x1, y1, x2, y2 = map(int, box.xyxy[0])
                        equipment_events.append({
                            "class": equip_class,
                            "track_id": track_id,
                            "score": conf,
                            "bbox": [x1, y1, x2, y2]
                        })

        # 2. Primary Person Detection & Identity Tracking
        pose_results = None
        has_people = False
        unknown_people = []
        people_boxes = {} # tid -> person bbox
        people_face_boxes = {} # tid -> estimated face bbox
        people_hands_visible = {} # tid -> bool

        yolo_pose = ModelManager().get_yolo_pose()
        if yolo_pose:
            pose_results = yolo_pose.track(frame, persist=True, tracker="botsort.yaml", verbose=False)
            if pose_results and pose_results[0].boxes:
                boxes = pose_results[0].boxes
                if hasattr(pose_results[0], 'keypoints') and pose_results[0].keypoints is not None:
                    kps_list = pose_results[0].keypoints.xy.cpu().numpy()
                    conf_list = pose_results[0].keypoints.conf.cpu().numpy() if pose_results[0].keypoints.conf is not None else None
                else:
                    kps_list = [None] * len(boxes)
                    conf_list = None
                    
                for i, box in enumerate(boxes):
                    if int(box.cls[0]) == 0:
                        has_people = True
                        tid = int(box.id[0]) if box.id is not None else -1
                        if tid != -1:
                            px1, py1, px2, py2 = map(int, box.xyxy[0])
                            people_boxes[tid] = [px1, py1, px2, py2]
                            
                            # Hands visibility from Pose (wrists are 9 and 10)
                            hands_visible = False
                            if conf_list is not None and len(conf_list) > i and conf_list[i] is not None and len(conf_list[i]) > 10:
                                lw_conf, rw_conf = conf_list[i][9], conf_list[i][10]
                                if lw_conf > 0.4 or rw_conf > 0.4:
                                    hands_visible = True
                            elif kps_list[i] is not None and len(kps_list[i]) > 10:
                                # Fallback if conf is not available
                                lw, rw = kps_list[i][9], kps_list[i][10]
                                if (lw[0] > 0 and lw[1] > 0) or (rw[0] > 0 and rw[1] > 0):
                                    hands_visible = True
                            
                            people_hands_visible[tid] = hands_visible
                            
                            # Estimate face box from keypoints
                            kps = kps_list[i]
                            face_bbox = None
                            if kps is not None and len(kps) >= 5:
                                face_kps = [p for p in kps[:5] if p[0] > 0 and p[1] > 0]
                                if len(face_kps) >= 2:
                                    xs = [p[0] for p in face_kps]
                                    ys = [p[1] for p in face_kps]
                                    pad = 30
                                    face_bbox = [int(min(xs))-pad, int(min(ys))-pad, int(max(xs))+pad, int(max(ys))+pad]
                            
                            if not face_bbox:
                                face_bbox = [px1, py1, px2, py1 + int((py2-py1)*0.3)]
                                
                            people_face_boxes[tid] = face_bbox

                            # Check identity cache
                            if tid not in self.identity_cache or self.identity_cache[tid]["name"] == "Unknown":
                                unknown_people.append(tid)
                            elif tid in self.identity_cache:
                                face_events.append({
                                    "tid": tid,
                                    "name": self.identity_cache[tid]["name"],
                                    "score": self.identity_cache[tid]["score"],
                                    "bbox": face_bbox,
                                    "kps": kps_list[i].tolist() if kps_list[i] is not None else None,
                                    "kps_conf": conf_list[i].tolist() if conf_list is not None and len(conf_list) > i and conf_list[i] is not None else None
                                })

        # 3. Heavy Downstream Models (Only if people are present)
        if has_people:
            # Face Detection (Only run if there are unknown people!)
            if unknown_people:
                app = ModelManager().get_face_analysis(self.config)
                faces = app.get(frame)
                
                for face in faces:
                    bbox = face.bbox.astype(int)
                    fx = (bbox[0] + bbox[2]) / 2
                    fy = (bbox[1] + bbox[3]) / 2
                    
                    # Match face to an unknown person track_id
                    matched_tid = None
                    for tid in unknown_people:
                        px1, py1, px2, py2 = people_boxes[tid]
                        if px1 <= fx <= px2 and py1 <= fy <= py2:
                            matched_tid = tid
                            break
                            
                    if not matched_tid:
                        continue # Face didn't match any person body

                    emb = face.embedding
                    emb_norm = np.linalg.norm(emb)
                    if emb_norm > 0:
                        emb = emb / emb_norm

                    best_match = "Unknown"
                    best_score = 0.0

                    if self.staff_embeddings_matrix.shape[0] > 0:
                        scores = np.dot(self.staff_embeddings_matrix, emb)
                        best_idx = np.argmax(scores)
                        best_score = float(scores[best_idx])
                        
                        if best_score >= self.rejection_threshold:
                            best_match = self.staff_names[best_idx]
                    
                    # Cache the result
                    self.identity_cache[matched_tid] = {"name": best_match, "score": best_score}
                    
                    face_events.append({
                        "tid": matched_tid,
                        "name": best_match,
                        "score": best_score,
                        "bbox": people_face_boxes[matched_tid],
                        # Add kps from the match. We need to find `i` for matched_tid.
                        # However, since we don't have `i` here easily, we'll just omit kps for newly recognized people for ONE frame.
                        # It's fine because next frame they'll be known and caught by the `elif tid in self.identity_cache:` block above.
                        "kps": None,
                        "kps_conf": None
                    })
                    
            # Cleanup old IDs from cache (optional, prevents memory leak)
            current_tids = set(people_boxes.keys())
            for tid in list(self.identity_cache.keys()):
                if tid not in current_tids and self.identity_cache[tid]["name"] == "Unknown":
                    del self.identity_cache[tid] # Forget unknown people quickly so we re-scan them


            hsv_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
            color_mask = self._get_dynamic_color_mask(hsv_frame)

            for face in face_events:
                face["has_mask"] = False
                face["has_gloves"] = False
                kps = face.get("kps")
                
                if kps is not None:
                    fh, fw = frame.shape[:2]
                    
                    # --- Mask Detection (Nose / Mouth Area) ---
                    nose = kps[0]
                    if nose[0] > 0 and nose[1] > 0:
                        nx, ny = int(nose[0]), int(nose[1])
                        # Box around mouth area
                        mx1, my1 = max(0, nx - 50), max(0, ny - 20)
                        mx2, my2 = min(fw, nx + 50), min(fh, ny + 80)
                        
                        roi = color_mask[my1:my2, mx1:mx2]
                        if roi.size > 0:
                            ratio = np.sum(roi > 0) / roi.size
                            if ratio > 0.50:
                                face["has_mask"] = True
                                ppe_events.append({"class": "Mask", "bbox": [mx1, my1, mx2, my2], "score": ratio})

                    # --- Gloves Detection (Wrists) ---
                    if len(kps) > 10:
                        for idx in [9, 10]: # Left and Right wrist
                            wrist = kps[idx]
                            if wrist[0] > 0 and wrist[1] > 0:
                                wx, wy = int(wrist[0]), int(wrist[1])
                                gx1, gy1 = max(0, wx - 45), max(0, wy - 45)
                                gx2, gy2 = min(fw, wx + 45), min(fh, wy + 45)
                                
                                roi = color_mask[gy1:gy2, gx1:gx2]
                                if roi.size > 0:
                                    ratio = np.sum(roi > 0) / roi.size
                                    if ratio > 0.35:
                                        face["has_gloves"] = True
                                        ppe_events.append({"class": "Gloves", "bbox": [gx1, gy1, gx2, gy2], "score": ratio})
                
                if face["has_mask"] and face["name"] == "Unknown":
                    upper_emb = self.extract_upper_embedding(img=frame, bbox=face["bbox"])
                    if upper_emb is not None and self.staff_upper_embeddings_matrix.shape[0] > 0:
                        u_norm = np.linalg.norm(upper_emb)
                        if u_norm > 0:
                            upper_emb = upper_emb / u_norm
                        scores = np.dot(self.staff_upper_embeddings_matrix, upper_emb)
                        best_idx = np.argmax(scores)
                        best_score = scores[best_idx]
                        if best_score >= self.rejection_threshold - 0.05:
                            face["name"] = self.staff_names[best_idx]
                            face["score"] = float(best_score)
                
                # Tracker
                bbox = face["bbox"]
                cx = (bbox[0] + bbox[2]) / 2
                cy = (bbox[1] + bbox[3]) / 2
                
                best_dist = float('inf')
                best_track_id = -1
                for tid, t in self.active_face_tracks.items():
                    if t.get("used", False): continue
                    tcx, tcy = t["centroid"]
                    dist = ((cx - tcx)**2 + (cy - tcy)**2)**0.5
                    if dist < best_dist:
                        best_dist = dist
                        best_track_id = tid
                        
                if best_dist < 300:
                    t = self.active_face_tracks[best_track_id]
                    if face["name"] == "Unknown" and t["name"] != "Unknown":
                        face["name"] = t["name"]
                        face["score"] = t["score"]
                    elif face["name"] != "Unknown":
                        t["name"] = face["name"]
                        t["score"] = face["score"]
                        
                    if face["has_mask"]:
                        t["mask_missed"] = 0
                        t["has_mask"] = True
                    else:
                        t["mask_missed"] = t.get("mask_missed", 0) + 1
                        if t["mask_missed"] < 10:
                            face["has_mask"] = t.get("has_mask", False)
                        else:
                            t["has_mask"] = False
                            
                    if face["has_gloves"]:
                        t["gloves_missed"] = 0
                        t["has_gloves"] = True
                    else:
                        t["gloves_missed"] = t.get("gloves_missed", 0) + 1
                        if t["gloves_missed"] < 20: # 20 frames memory for gloves since they move faster
                            face["has_gloves"] = t.get("has_gloves", False)
                        else:
                            t["has_gloves"] = False
                        
                    t["centroid"] = (cx, cy)
                    t["missed"] = 0
                    t["used"] = True
                else:
                    self.active_face_tracks[self.next_track_id] = {
                        "centroid": (cx, cy),
                        "name": face["name"],
                        "score": face["score"],
                        "has_mask": face["has_mask"],
                        "mask_missed": 0,
                        "has_gloves": face["has_gloves"],
                        "gloves_missed": 0,
                        "missed": 0,
                        "used": True
                    }
                    self.next_track_id += 1

        # 4. Incident Detection (Falls, Theft, Obscured Face)
        if pose_results and pose_results[0].boxes:
            boxes = pose_results[0].boxes
            keypoints = pose_results[0].keypoints
            for i, box in enumerate(boxes):
                cls_id = int(box.cls[0])
                if cls_id == 0:  # Person
                    conf = float(box.conf[0])
                    x1, y1, x2, y2 = map(int, box.xyxy[0])
                    width = x2 - x1
                    height = y2 - y1
                    
                    kps = None
                    if keypoints is not None and hasattr(keypoints, 'xy') and keypoints.xy is not None and len(keypoints.xy) > i:
                        kps = keypoints.xy[i]

                    # Fall Detection
                    is_fall = False
                    if width > height * 1.1 and conf > 0.5:
                        if kps is not None and len(kps) > 12:
                            head_y = kps[0][1]
                            left_hip_y, right_hip_y = kps[11][1], kps[12][1]
                            if head_y > 0 and left_hip_y > 0 and right_hip_y > 0:
                                hip_y = (left_hip_y + right_hip_y) / 2.0
                                torso_height = hip_y - head_y
                                if torso_height < (height * 0.25):
                                    is_fall = True
                        else:
                            if width > height * 1.5:
                                is_fall = True
                                
                    if is_fall:
                        incident_events.append({
                            "type": "fall",
                            "bbox": [x1, y1, x2, y2]
                        })
                    
                    # Theft
                    if kps is not None and len(kps) > 10:
                        left_wrist = kps[9]
                        right_wrist = kps[10]
                        for eq in equipment_events:
                            eq_x1, eq_y1, eq_x2, eq_y2 = eq["bbox"]
                            def in_bbox(pt, bx1, by1, bx2, by2):
                                return bx1 <= pt[0] <= bx2 and by1 <= pt[1] <= by2
                            is_touching = False
                            if left_wrist[0] > 0 and left_wrist[1] > 0 and in_bbox(left_wrist, eq_x1, eq_y1, eq_x2, eq_y2):
                                is_touching = True
                            if right_wrist[0] > 0 and right_wrist[1] > 0 and in_bbox(right_wrist, eq_x1, eq_y1, eq_x2, eq_y2):
                                is_touching = True
                                
                            if is_touching:
                                person_name = "Unknown"
                                for face in face_events:
                                    fx1, fy1, fx2, fy2 = face["bbox"]
                                    fcx, fcy = (fx1 + fx2) // 2, (fy1 + fy2) // 2
                                    if x1 <= fcx <= x2 and y1 <= fcy <= y2:
                                        person_name = face["name"]
                                        break
                                if person_name == "Unknown":
                                    incident_events.append({
                                        "type": "theft",
                                        "bbox": [x1, y1, x2, y2],
                                        "equipment": eq["class"]
                                    })
                                    break
                                    
                    # Obscured Face
                    has_face = False
                    for face in face_events:
                        fx1, fy1, fx2, fy2 = face["bbox"]
                        fcx, fcy = (fx1 + fx2) // 2, (fy1 + fy2) // 2
                        if x1 <= fcx <= x2 and y1 <= fcy <= y2:
                            has_face = True
                            break
                            
                    if not has_face and width > 100 and height > 150:
                        reason = "Face is obscured, covered, or turned away"
                        if kps is not None and len(kps) > 10:
                            nose = kps[0]
                            l_wrist = kps[9]
                            r_wrist = kps[10]
                            head_threshold = height * 0.25
                            def dist(p1, p2):
                                return ((p1[0] - p2[0])**2 + (p1[1] - p2[1])**2)**0.5
                            if (l_wrist[0] > 0 and nose[0] > 0 and dist(l_wrist, nose) < head_threshold) or \
                               (r_wrist[0] > 0 and nose[0] > 0 and dist(r_wrist, nose) < head_threshold):
                                reason = "Hand is covering face"
                        incident_events.append({
                            "type": "obscured_face",
                            "bbox": [x1, y1, x2, y2],
                            "reason": reason
                        })

        # Cleanup tracker
        new_active_tracks = {}
        for tid, t in self.active_face_tracks.items():
            if not t.get("used", False):
                t["missed"] += 1
            t["used"] = False
            if t["missed"] < 10:
                new_active_tracks[tid] = t
        self.active_face_tracks = new_active_tracks

        return frame, face_events, equipment_events, incident_events, ppe_events



# Singleton instance — initialised once at startup
vision_service = VisionService()
