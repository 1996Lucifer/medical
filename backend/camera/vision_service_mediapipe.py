import cv2
import numpy as np
import os
import json
import mediapipe as mp
from mediapipe.tasks.python.vision import drawing_utils
from mediapipe.tasks.python.vision import drawing_styles
from mediapipe.tasks.python.vision import FaceLandmarksConnections, HandLandmarksConnections, PoseLandmarksConnections
from camera.model_manager import ModelManager

# Constants
REJECTION_THRESHOLD = 0.5

class VisionServiceMediapipe:
    def __init__(self):
        print("[VisionServiceMediapipe] Initializing lightweight geometry-based vision service...")
        
        # Determine optimal backend config
        import onnxruntime as ort
        providers = ort.get_available_providers()
        if "CUDAExecutionProvider" in providers:
            self.config = {"ctx_id": 0, "det_size": (640, 640)}
        elif "CoreMLExecutionProvider" in providers:
            self.config = {"ctx_id": 0, "det_size": (640, 640)}
        else:
            self.config = {"ctx_id": -1, "det_size": (320, 320)}
            
        self.staff_names = []
        self.staff_embeddings_matrix = np.empty((0, 512))
        self.staff_upper_embeddings_matrix = np.empty((0, 512))
        
        self.active_face_tracks = {}
        self.next_track_id = 0
        self.identity_cache = {}
        
        # Temporal smoothing for PPE
        self.mask_confidence = 0
        self.glove_confidence = 0
        
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
            
            # Using same full embedding for upper face temporarily as fallback
            upper_embeddings.append(emb)

        if embeddings:
            self.staff_embeddings_matrix = np.vstack(embeddings)
            self.staff_upper_embeddings_matrix = np.vstack(upper_embeddings)
        else:
            self.staff_embeddings_matrix = np.empty((0, 512))
            self.staff_upper_embeddings_matrix = np.empty((0, 512))

    def process_frame(self, frame):
        """
        Lightweight pipeline using MediaPipe Holistic for everything.
        No YOLO required.
        """
        original_frame = frame.copy()
        face_events = []
        equipment_events = []
        incident_events = []
        ppe_events = []

        fh, fw = frame.shape[:2]
        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        
        mp_holistic = ModelManager().get_mp_holistic()
        if not mp_holistic:
            return frame, face_events, equipment_events, incident_events, ppe_events

        results = mp_holistic.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame))
        
        # Visualizations will be drawn after detecting masks and gloves
        
        hsv_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
        color_mask = self._get_dynamic_color_mask(hsv_frame)

        raw_has_mask = False
        raw_has_gloves = False
        face_bbox = None

        # 1. Fall Detection (Pose)
        if results.pose_landmarks and len(results.pose_landmarks) > 0:
            landmarks = results.pose_landmarks
            nose = landmarks[0]
            left_hip = landmarks[23]
            right_hip = landmarks[24]
            
            # Simple Geometry: If nose is below hips, trigger Fall
            if nose.visibility > 0.5 and left_hip.visibility > 0.5 and right_hip.visibility > 0.5:
                avg_hip_y = (left_hip.y + right_hip.y) / 2.0
                if nose.y > avg_hip_y:
                    # Provide a bounding box covering the fallen person using hip/nose coords
                    xs = [int(nose.x * fw), int(left_hip.x * fw), int(right_hip.x * fw)]
                    ys = [int(nose.y * fh), int(left_hip.y * fh), int(right_hip.y * fh)]
                    fall_bbox = [max(0, min(xs)-50), max(0, min(ys)-50), min(fw, max(xs)+50), min(fh, max(ys)+50)]
                    incident_events.append({"type": "fall", "score": 0.95, "bbox": fall_bbox})
                    # Draw warning box
                    cv2.putText(frame, "FALL DETECTED", (50, 50), cv2.FONT_HERSHEY_SIMPLEX, 1, (0,0,255), 3)

        # 2. Pixel-Perfect Mask Detection (Face Mesh)
        if results.face_landmarks and len(results.face_landmarks) > 0:
            landmarks = results.face_landmarks
            
            # Calculate Face Bounding Box for Identity
            xs = [lm.x * fw for lm in landmarks]
            ys = [lm.y * fh for lm in landmarks]
            face_bbox = [int(min(xs)), int(min(ys)), int(max(xs)), int(max(ys))]
            
            # Lower Face Polygon for Mask (Chin 152, Left cheek 234, Right cheek 454, Nose bridge 197)
            # We'll use a set of landmarks outlining the mouth/nose area
            mask_indices = [197, 114, 234, 152, 454, 343]
            poly_points = np.array([[int(landmarks[i].x * fw), int(landmarks[i].y * fh)] for i in mask_indices], np.int32)
            poly_points = poly_points.reshape((-1, 1, 2))
            
            # Create blank mask and draw polygon
            poly_mask = np.zeros((fh, fw), dtype=np.uint8)
            cv2.fillPoly(poly_mask, [poly_points], 255)
            
            # Check intersection with color mask
            roi_color = cv2.bitwise_and(color_mask, poly_mask)
            poly_area = np.sum(poly_mask == 255)
            
            if poly_area > 0:
                color_pixels = np.sum(roi_color > 0)
                ratio = color_pixels / poly_area
                if ratio > 0.25:
                    raw_has_mask = True
                    # Draw perfect mask polygon on screen instead of a box
                    cv2.polylines(frame, [poly_points], isClosed=True, color=(0, 165, 255), thickness=2)
                    cv2.putText(frame, f"Mask {int(ratio*100)}%", (int(min(xs)), int(min(ys))-10), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 165, 255), 2)

        # 3. Pixel-Perfect Gloves Detection (Hands + Wrists Fallback)
        hand_lists = []
        if getattr(results, 'left_hand_landmarks', None):
            hand_lists.append(results.left_hand_landmarks)
        if getattr(results, 'right_hand_landmarks', None):
            hand_lists.append(results.right_hand_landmarks)
            
        for hand_lm in hand_lists:
            # If MediaPipe successfully found the hand (even with a tight glove)
            pts = np.array([[int(lm.x * fw), int(lm.y * fh)] for lm in hand_lm], dtype=np.int32)
            hull = cv2.convexHull(pts)
            if len(hull) > 2:
                poly_area = cv2.contourArea(hull)
                hand_mask = np.zeros((fh, fw), dtype=np.uint8)
                cv2.fillPoly(hand_mask, [hull], 255)
                roi_color = cv2.bitwise_and(color_mask, hand_mask)
                if poly_area > 0:
                    ratio = np.sum(roi_color > 0) / poly_area
                    if ratio > 0.15:
                        raw_has_gloves = True
                        cv2.polylines(frame, [hull], isClosed=True, color=(0, 165, 255), thickness=2)
                        cv2.putText(frame, f"Gloves {int(ratio*100)}%", (int(np.min(pts[:,0])), int(np.min(pts[:,1]))-10), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 165, 255), 2)

        # Fallback: If no hands detected (due to featureless loose glove), check wrists
        if not raw_has_gloves and getattr(results, 'pose_landmarks', None) and len(results.pose_landmarks) > 16:
            for idx in [15, 16]: # Left and Right wrist
                wrist = results.pose_landmarks[idx]
                if wrist.visibility > 0.3:
                    wx, wy = int(wrist.x * fw), int(wrist.y * fh)
                    gx1, gy1 = max(0, wx - 60), max(0, wy - 60)
                    gx2, gy2 = min(fw, wx + 60), min(fh, wy + 60)
                    roi = color_mask[gy1:gy2, gx1:gx2]
                    if roi.size > 0:
                        ratio = np.sum(roi > 0) / roi.size
                        if ratio > 0.20:
                            raw_has_gloves = True
                            pts = np.array([[gx1, gy1], [gx2, gy1], [gx2, gy2], [gx1, gy2]], np.int32)
                            cv2.polylines(frame, [pts], isClosed=True, color=(0, 165, 255), thickness=2)
                            cv2.putText(frame, f"Gloves {int(ratio*100)}%", (gx1, gy1-10), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 165, 255), 2)

        # Apply Temporal Smoothing (Debounce)
        if raw_has_mask:
            self.mask_confidence = min(15, self.mask_confidence + 3)
        else:
            self.mask_confidence = max(0, self.mask_confidence - 1)
            
        if raw_has_gloves:
            self.glove_confidence = min(15, self.glove_confidence + 3)
        else:
            self.glove_confidence = max(0, self.glove_confidence - 1)
            
        has_mask = self.mask_confidence > 5
        has_gloves = self.glove_confidence > 5

        # --- DRAW VISUALIZATIONS (Conditionally) ---
        point_spec = drawing_utils.DrawingSpec(color=(0, 255, 0), thickness=2, circle_radius=2)
        line_spec = drawing_utils.DrawingSpec(color=(255, 255, 255), thickness=2)
        
        # Draw Pose (Always draw pose skeleton)
        if results.pose_landmarks:
            drawing_utils.draw_landmarks(
                frame,
                results.pose_landmarks,
                PoseLandmarksConnections.POSE_LANDMARKS,
                landmark_drawing_spec=point_spec,
                connection_drawing_spec=line_spec
            )
            
        # Draw Face Mesh ONLY if no mask is intruding
        if not has_mask and results.face_landmarks:
            drawing_utils.draw_landmarks(
                frame,
                results.face_landmarks,
                FaceLandmarksConnections.FACE_LANDMARKS_TESSELATION,
                landmark_drawing_spec=point_spec,
                connection_drawing_spec=line_spec
            )
            drawing_utils.draw_landmarks(
                frame,
                results.face_landmarks,
                FaceLandmarksConnections.FACE_LANDMARKS_CONTOURS,
                landmark_drawing_spec=point_spec,
                connection_drawing_spec=line_spec
            )
            
        # Draw Hands ONLY if no gloves are intruding
        if not has_gloves:
            if getattr(results, 'left_hand_landmarks', None):
                drawing_utils.draw_landmarks(
                    frame,
                    results.left_hand_landmarks,
                    HandLandmarksConnections.HAND_CONNECTIONS,
                    landmark_drawing_spec=point_spec,
                    connection_drawing_spec=line_spec
                )
            if getattr(results, 'right_hand_landmarks', None):
                drawing_utils.draw_landmarks(
                    frame,
                    results.right_hand_landmarks,
                    HandLandmarksConnections.HAND_CONNECTIONS,
                    landmark_drawing_spec=point_spec,
                    connection_drawing_spec=line_spec
                )
        # ---------------------------        # 4. Identity Recognition
        if face_bbox:
            # We only have one person in this lightweight pipeline
            tid = 0
            best_match = "Unknown"
            best_score = 0.0
            
            # Simple identity check every 30 frames or if unknown
            if tid not in self.identity_cache or self.identity_cache[tid]["name"] == "Unknown":
                app = ModelManager().get_face_analysis(self.config)
                if app:
                    faces = app.get(original_frame)
                    if faces:
                        # Find face closest to our bbox center
                        fx1, fy1, fx2, fy2 = face_bbox
                        fcx, fcy = (fx1 + fx2) / 2, (fy1 + fy2) / 2
                        best_dist = float('inf')
                        best_face = None
                        
                        for face in faces:
                            bx1, by1, bx2, by2 = face.bbox.astype(int)
                            cx, cy = (bx1 + bx2) / 2, (by1 + by2) / 2
                            # Calculate squared distance between centers
                            dist = (cx - fcx)**2 + (cy - fcy)**2
                            if dist < best_dist:
                                best_dist = dist
                                best_face = face
                                
                        if best_face:
                            emb = best_face.embedding
                            emb_norm = np.linalg.norm(emb)
                            if emb_norm > 0:
                                emb = emb / emb_norm
                            if self.staff_embeddings_matrix.shape[0] > 0:
                                scores = np.dot(self.staff_embeddings_matrix, emb)
                                best_idx = np.argmax(scores)
                                best_score = float(scores[best_idx])
                                print(f"[DEBUG IDENTITY] Best Match: {self.staff_names[best_idx]} - Score: {best_score}")
                                if best_score >= REJECTION_THRESHOLD:
                                    best_match = self.staff_names[best_idx]
                            else:
                                print("[DEBUG IDENTITY] staff_embeddings_matrix is EMPTY!")
                        else:
                            print("[DEBUG IDENTITY] No closest face found in detection!")
                    else:
                        print(f"[DEBUG IDENTITY] InsightFace detected 0 faces in the frame. face_bbox={face_bbox}")
                self.identity_cache[tid] = {"name": best_match, "score": best_score}
            else:
                best_match = self.identity_cache[tid]["name"]
                best_score = self.identity_cache[tid]["score"]

            face_events.append({
                "tid": tid,
                "name": best_match,
                "score": best_score,
                "bbox": face_bbox,
                "has_mask": has_mask,
                "has_gloves": has_gloves,
                "kps": None
            })
            
            # Draw Face Name
            fx1, fy1, fx2, fy2 = face_bbox
            cv2.rectangle(frame, (fx1, fy1), (fx2, fy2), (0, 255, 0), 2)
            cv2.putText(frame, f"{best_match} {int(best_score*100)}%", (fx1, fy1-10), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)


        return frame, face_events, equipment_events, incident_events, ppe_events

vision_service = VisionServiceMediapipe()
