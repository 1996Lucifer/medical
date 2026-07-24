import cv2
import mediapipe as mp
import numpy as np
from mediapipe.solutions import drawing_utils
from mediapipe.solutions import face_mesh
from mediapipe.framework.formats import landmark_pb2
from camera.model_manager import ModelManager

frame = cv2.imread("uploads/staff/93a9324a7ee445fa9e0bb7d4fb2c3d32_front.jpg")
rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

mp_holistic = ModelManager().get_mp_holistic()
results = mp_holistic.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))

if results.face_landmarks:
    point_spec = drawing_utils.DrawingSpec(color=(0, 255, 0), thickness=2, circle_radius=2)
    line_spec = drawing_utils.DrawingSpec(color=(255, 255, 255), thickness=1)
    
    # Convert list of NormalizedLandmark to NormalizedLandmarkList protobuf
    face_landmarks_proto = landmark_pb2.NormalizedLandmarkList()
    face_landmarks_proto.landmark.extend([
        landmark_pb2.NormalizedLandmark(x=lm.x, y=lm.y, z=lm.z) for lm in results.face_landmarks
    ])

    try:
        drawing_utils.draw_landmarks(
            frame,
            face_landmarks_proto,
            face_mesh.FACEMESH_TESSELATION,
            landmark_drawing_spec=None, # Tesselation shouldn't have points drawn usually
            connection_drawing_spec=line_spec
        )
        print("TESSELATION SUCCESS")
    except Exception as e:
        print("TESSELATION FAILED:", e)

