import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision
import numpy as np

base_options = python.BaseOptions(model_asset_path='models/holistic_landmarker.task')
options = vision.HolisticLandmarkerOptions(base_options=base_options)
detector = vision.HolisticLandmarker.create_from_options(options)

rgb_frame = np.zeros((480, 640, 3), dtype=np.uint8)
mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame)
results = detector.detect(mp_image)

print(type(results.face_landmarks))
if len(results.face_landmarks) > 0:
    print(type(results.face_landmarks[0]))
    print(len(results.face_landmarks[0]))
else:
    print("No faces detected in black image")
