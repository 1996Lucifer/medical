import numpy as np

frame = np.zeros((480, 640, 3), dtype=np.uint8)

from mediapipe.tasks.python.vision import drawing_utils
from mediapipe.tasks.python.vision import FaceLandmarksConnections

# Create fake landmarks
from mediapipe.framework.formats import landmark_pb2


class FakeLandmarks:
    pass


lms = []
for i in range(478):
    lms.append(landmark_pb2.NormalizedLandmark(x=0.5, y=0.5, z=0.5))

point_spec = drawing_utils.DrawingSpec(color=(0, 255, 0), thickness=2, circle_radius=2)
line_spec = drawing_utils.DrawingSpec(color=(255, 255, 255), thickness=1)

# Just use line_spec for ALL connections!
try:
    drawing_utils.draw_landmarks(
        frame,
        lms,
        FaceLandmarksConnections.FACE_LANDMARKS_CONTOURS,
        landmark_drawing_spec=point_spec,
        connection_drawing_spec=line_spec,
    )
    print("SUCCESS")
except Exception as e:
    print("FAILED:", e)
