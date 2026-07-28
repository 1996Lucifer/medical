import cv2
import numpy as np
import os
import time
from typing import Optional, Tuple, List, Dict

import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

from camera.model_manager import ModelManager

class VisionServiceTexture:
    """
    A lightweight, plug-and-play alternative to VisionServiceZones.
    Uses MediaPipe Holistic for Face, Hands, and Pose, combined with
    texture variance (Laplacian) to detect masks and avoid false positives on bare faces.
    """
    def __init__(self, camera_name: str = "Unknown Camera"):
        print("[VisionServiceTexture] Initializing Texture-based Vision Service...")
        self.camera_name = camera_name
        self.staff_names = []
        self.staff_embeddings_matrix = np.empty((0, 512))
        self.identity_cache = {}
        self.next_track_id = 1
        
        # Determine config for InsightFace
        from camera.constants.vision_constants import get_runtime_vision_config
        self.config = get_runtime_vision_config()
        self.config_dict = {
            "ctx_id": self.config["ctx_id"],
            "det_size": self.config["det_size"]
        }

    def update_staff_embeddings(self, staff_list: list) -> None:
        self.staff_names = []
        embeddings = []
        for staff in staff_list:
            self.staff_names.append(staff["name"])
            emb = np.asarray(staff["embedding"], dtype=np.float32)
            norm = np.linalg.norm(emb)
            if norm > 0:
                emb = emb / norm
            embeddings.append(emb)

        if embeddings:
            self.staff_embeddings_matrix = np.vstack(embeddings)
        else:
            self.staff_embeddings_matrix = np.empty((0, 512))

    def update_zone_polygons(self, zones: list) -> None:
        # Texture experimental service does not heavily use zones yet, but stub is required for interface compatibility
        self.zone_polygons = zones

    def _get_texture_variance(self, image_bgr: np.ndarray, polygon_pts: np.ndarray) -> Tuple[float, float]:
        """
        Calculates Laplacian variance and Color Standard Deviation inside a polygon.
        """
        mask = np.zeros(image_bgr.shape[:2], dtype=np.uint8)
        cv2.fillPoly(mask, [polygon_pts], 255)
        
        gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
        laplacian = cv2.Laplacian(gray, cv2.CV_64F)
        
        pts = np.where(mask == 255)
        if len(pts[0]) == 0:
            return 0.0, 0.0
            
        laplacian_vals = laplacian[pts[0], pts[1]]
        texture_var = np.var(laplacian_vals)
        
        hsv = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2HSV)
        v_channel = hsv[:,:,2]
        v_vals = v_channel[pts[0], pts[1]]
        color_std = np.std(v_vals)
        
        return float(texture_var), float(color_std)

    def process_frame(
        self, frame: np.ndarray, camera_id: Optional[int] = None
    ) -> Tuple[np.ndarray, list, list, list, list]:
        """
        Main processing pipeline compatible with vision_worker.py expectations.
        """
        original_frame = frame.copy()
        fh, fw = frame.shape[:2]

        face_events = []
        equipment_events = []
        incident_events = []
        ppe_events = []

        mp_holistic = ModelManager().get_mp_holistic()
        if not mp_holistic:
            return frame, face_events, equipment_events, incident_events, ppe_events

        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame)
        results = mp_holistic.detect(mp_image)

        has_mask = False
        has_gloves = False
        face_bbox = None

        # 1. Fall Detection via Pose
        if results.pose_landmarks and len(results.pose_landmarks) > 0:
            landmarks = results.pose_landmarks
            # Simple fallback check for fall
            nose = landmarks[0]
            left_hip = landmarks[23]
            right_hip = landmarks[24]
            if nose.visibility > 0.5 and left_hip.visibility > 0.5:
                if nose.y > ((left_hip.y + right_hip.y) / 2):
                    incident_events.append({
                        "type": "fall", 
                        "bbox": [
                            max(0, int(nose.x*fw)-50), max(0, int(nose.y*fh)-50),
                            min(fw, int(left_hip.x*fw)+50), min(fh, int(left_hip.y*fh)+50)
                        ]
                    })

        # 2. Face and Mask Detection
        if results.face_landmarks and len(results.face_landmarks) > 0:
            landmarks = results.face_landmarks
            
            xs = [lm.x * fw for lm in landmarks]
            ys = [lm.y * fh for lm in landmarks]
            face_bbox = [int(min(xs)), int(min(ys)), int(max(xs)), int(max(ys))]
            
            # Extract Mask Polygon (Lower Face)
            mask_indices = [152, 377, 454, 197, 234, 148]
            poly_points = np.array([[int(landmarks[i].x * fw), int(landmarks[i].y * fh)] for i in mask_indices], np.int32)
            
            texture_var, color_std = self._get_texture_variance(original_frame, poly_points)
            
            # Thresholds
            if texture_var < 50.0 and color_std < 40.0:
                has_mask = True
                ppe_events.append({"class": "Mask", "bbox": face_bbox, "score": 1.0})
                
            # Identity Verification (Run InsightFace on the cropped face to save time)
            best_match = "Unknown"
            best_score = 0.0
            
            fx1, fy1, fx2, fy2 = face_bbox
            # Add padding
            pad = 20
            cx1, cy1 = max(0, fx1-pad), max(0, fy1-pad)
            cx2, cy2 = min(fw, fx2+pad), min(fh, fy2+pad)
            face_crop = original_frame[cy1:cy2, cx1:cx2]
            
            if face_crop.size > 0:
                app = ModelManager().get_face_analysis(self.config_dict)
                if app:
                    faces = app.get(face_crop)
                    if faces:
                        best_face = max(faces, key=lambda f: (f.bbox[2]-f.bbox[0])*(f.bbox[3]-f.bbox[1]))
                        emb = best_face.embedding
                        emb_norm = np.linalg.norm(emb)
                        if emb_norm > 0:
                            emb = emb / emb_norm
                        
                        if self.staff_embeddings_matrix.shape[0] > 0:
                            scores = np.dot(self.staff_embeddings_matrix, emb)
                            best_idx = int(np.argmax(scores))
                            best_score = float(scores[best_idx])
                            
                            from camera.constants.vision_constants import REJECTION_THRESHOLD
                            if best_score >= REJECTION_THRESHOLD:
                                best_match = self.staff_names[best_idx]
                                
            face_events.append({
                "tid": self.next_track_id,
                "name": best_match,
                "score": best_score,
                "bbox": face_bbox,
                "has_mask": has_mask,
                "has_gloves": False,
                "kps": None
            })

        # 3. Glove Detection
        if results.left_hand_landmarks:
            hand_landmarks = results.left_hand_landmarks
            xs = [lm.x * fw for lm in hand_landmarks]
            ys = [lm.y * fh for lm in hand_landmarks]
            hbox = [int(min(xs)), int(min(ys)), int(max(xs)), int(max(ys))]
            ppe_events.append({"class": "Gloves", "bbox": hbox, "score": 1.0})
            if face_events:
                face_events[0]["has_gloves"] = True
                
        if results.right_hand_landmarks:
            hand_landmarks = results.right_hand_landmarks
            xs = [lm.x * fw for lm in hand_landmarks]
            ys = [lm.y * fh for lm in hand_landmarks]
            hbox = [int(min(xs)), int(min(ys)), int(max(xs)), int(max(ys))]
            ppe_events.append({"class": "Gloves", "bbox": hbox, "score": 1.0})
            if face_events:
                face_events[0]["has_gloves"] = True
                    
        return frame, face_events, equipment_events, incident_events, ppe_events

