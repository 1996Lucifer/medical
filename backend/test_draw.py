import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision
import numpy as np
import cv2

base_options = python.BaseOptions(model_asset_path='models/holistic_landmarker.task')
options = vision.HolisticLandmarkerOptions(base_options=base_options)
detector = vision.HolisticLandmarker.create_from_options(options)

rgb_frame = np.zeros((480, 640, 3), dtype=np.uint8)
mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame)
results = detector.detect(mp_image)

from mediapipe.tasks.python.vision import drawing_utils
from mediapipe.tasks.python.vision import drawing_styles
from mediapipe.tasks.python.vision import FaceLandmarksConnections, HandLandmarksConnections, PoseLandmarksConnections

print("Imports ok, testing names:")
print(hasattr(FaceLandmarksConnections, 'FACE_LANDMARKS_TESSELATION'))
print(hasattr(HandLandmarksConnections, 'HAND_CONNECTIONS'))
print(hasattr(PoseLandmarksConnections, 'POSE_LANDMARKS'))

try:
    drawing_utils.draw_landmarks(rgb_frame, results.pose_landmarks, PoseLandmarksConnections.POSE_LANDMARKS, drawing_styles.get_default_pose_landmarks_style())
except Exception as e:
    print(f"Error: {e}")
