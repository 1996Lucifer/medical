import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision
import numpy as np
import cv2

base_options = python.BaseOptions(model_asset_path='models/holistic_landmarker.task')
options = vision.HolisticLandmarkerOptions(base_options=base_options)
detector = vision.HolisticLandmarker.create_from_options(options)

# Create a fake image that contains something, or capture from webcam for 1 frame
cap = cv2.VideoCapture(0)
ret, frame = cap.read()
if ret:
    rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame)
    results = detector.detect(mp_image)

    print("Pose:", type(results.pose_landmarks))
    if results.pose_landmarks:
        print("Pose len:", len(results.pose_landmarks))
        print("Pose[0] type:", type(results.pose_landmarks[0]))
        if isinstance(results.pose_landmarks[0], list):
            print("Pose[0] len:", len(results.pose_landmarks[0]))

    print("Face:", type(results.face_landmarks))
    if results.face_landmarks:
        print("Face len:", len(results.face_landmarks))
        print("Face[0] type:", type(results.face_landmarks[0]))
        if isinstance(results.face_landmarks[0], list):
            print("Face[0] len:", len(results.face_landmarks[0]))
else:
    print("Failed to grab frame")
cap.release()
