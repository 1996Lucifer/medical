import cv2
import numpy as np
import os
import sys

# Ensure backend directory is in path for imports
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

def get_texture_variance(image_bgr, polygon_pts):
    """
    Calculates the Laplacian variance (texture detail) and color std dev within a polygon.
    """
    mask = np.zeros(image_bgr.shape[:2], dtype=np.uint8)
    cv2.fillPoly(mask, [polygon_pts], 255)
    
    # Calculate Laplacian for texture variance
    gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    laplacian = cv2.Laplacian(gray, cv2.CV_64F)
    
    # Get pixels inside mask
    pts = np.where(mask == 255)
    if len(pts[0]) == 0:
        return 0.0, 0.0
        
    laplacian_vals = laplacian[pts[0], pts[1]]
    texture_var = np.var(laplacian_vals)
    
    # Color variance (std dev)
    hsv = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2HSV)
    v_channel = hsv[:,:,2]
    v_vals = v_channel[pts[0], pts[1]]
    color_std = np.std(v_vals)
    
    return float(texture_var), float(color_std)

def main():
    print("Initializing MediaPipe Holistic Landmarker...")
    model_path = os.path.join(os.path.dirname(__file__), "..", "models", "holistic_landmarker.task")
    
    if not os.path.exists(model_path):
        print(f"Error: Could not find holistic_landmarker.task at {model_path}")
        return
        
    base_options = python.BaseOptions(model_asset_path=model_path)
    options = vision.HolisticLandmarkerOptions(base_options=base_options)
    landmarker = vision.HolisticLandmarker.create_from_options(options)
    
    print("Opening Webcam (Press 'q' to quit)...")
    cap = cv2.VideoCapture(0)
    
    if not cap.isOpened():
        print("Error: Could not open webcam.")
        return

    while True:
        ret, frame = cap.read()
        if not ret:
            break
            
        fh, fw = frame.shape[:2]
        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame)
        
        results = landmarker.detect(mp_image)
        
        # Check Face Landmarks
        if results.face_landmarks and len(results.face_landmarks) > 0:
            # tasks API face_landmarks is a flat list
            landmarks = results.face_landmarks
            
            # Lower Face Polygon for Mask
            # 152: chin, 377: right jaw, 454: right cheek, 197: nose bridge, 234: left cheek, 148: left jaw
            mask_indices = [152, 377, 454, 197, 234, 148]
            
            poly_points = np.array([[int(landmarks[i].x * fw), int(landmarks[i].y * fh)] for i in mask_indices], np.int32)
            
            texture_var, color_std = get_texture_variance(frame, poly_points)
            
            # Heuristic thresholds (may need tuning)
            # Low texture variance = flat surface (mask)
            # High texture variance = lips, skin pores, facial hair (bare face)
            if texture_var < 50.0 and color_std < 40.0:
                label = "MASK DETECTED"
                color = (0, 255, 0)
            else:
                label = "BARE FACE"
                color = (0, 0, 255)
                
            cv2.polylines(frame, [poly_points], True, color, 2)
            cv2.putText(frame, f"{label}", (poly_points[3][0] - 50, poly_points[3][1] - 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, color, 2)
            cv2.putText(frame, f"Tex Var: {texture_var:.1f}", (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255,255,255), 2)
            cv2.putText(frame, f"Col Std: {color_std:.1f}", (10, 60), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255,255,255), 2)

        # Hand Landmarks for Gloves
        if results.right_hand_landmarks:
            hand_landmarks = results.right_hand_landmarks
            xs = [lm.x * fw for lm in hand_landmarks]
            ys = [lm.y * fh for lm in hand_landmarks]
            cv2.rectangle(frame, (int(min(xs)), int(min(ys))), (int(max(xs)), int(max(ys))), (255, 165, 0), 2)
            cv2.putText(frame, "Hand/Glove", (int(min(xs)), int(min(ys)) - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 165, 0), 2)

        if results.left_hand_landmarks:
            hand_landmarks = results.left_hand_landmarks
            xs = [lm.x * fw for lm in hand_landmarks]
            ys = [lm.y * fh for lm in hand_landmarks]
            cv2.rectangle(frame, (int(min(xs)), int(min(ys))), (int(max(xs)), int(max(ys))), (255, 165, 0), 2)
            cv2.putText(frame, "Hand/Glove", (int(min(xs)), int(min(ys)) - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 165, 0), 2)

        cv2.imshow("PPE Texture Experiment", frame)
        
        if cv2.waitKey(1) & 0xFF == ord('q'):
            break
            
    cap.release()
    cv2.destroyAllWindows()

if __name__ == "__main__":
    main()
