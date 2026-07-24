import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks.python.vision import drawing_utils
from mediapipe.tasks.python.vision import FaceLandmarksConnections
from camera.model_manager import ModelManager
import traceback

frame = cv2.imread("uploads/staff/93a9324a7ee445fa9e0bb7d4fb2c3d32_front.jpg")
rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

mp_holistic = ModelManager().get_mp_holistic()
results = mp_holistic.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))

if results.face_landmarks:
    point_spec = drawing_utils.DrawingSpec(color=(0, 255, 0), thickness=2, circle_radius=2)
    line_spec = drawing_utils.DrawingSpec(color=(255, 255, 255), thickness=1)
    try:
        drawing_utils.draw_landmarks(
            frame,
            results.face_landmarks,
            FaceLandmarksConnections.FACE_LANDMARKS_TESSELATION,
            landmark_drawing_spec=point_spec,
            connection_drawing_spec=line_spec
        )
        print("TESSELATION SUCCESS")
    except Exception as e:
        traceback.print_exc()

