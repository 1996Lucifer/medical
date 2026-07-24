import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision
import numpy as np
import cv2

base_options = python.BaseOptions(model_asset_path='models/holistic_landmarker.task')
options = vision.HolisticLandmarkerOptions(base_options=base_options)
detector = vision.HolisticLandmarker.create_from_options(options)

import urllib.request
# Download an image of a person
urllib.request.urlretrieve("https://raw.githubusercontent.com/google/mediapipe/master/mediapipe/python/solutions/face_mesh_test.jpg", "test_person.jpg")
rgb_frame = cv2.imread("test_person.jpg")
if rgb_frame is not None:
    rgb_frame = cv2.cvtColor(rgb_frame, cv2.COLOR_BGR2RGB)
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame)
    results = detector.detect(mp_image)

    from mediapipe.tasks.python.vision import drawing_utils, drawing_styles, FaceLandmarksConnections
    
    print("Detected Face:", bool(results.face_landmarks))
    if results.face_landmarks:
        print("Face List Length:", len(results.face_landmarks))
        
        # Test Drawing
        bgr_frame = cv2.cvtColor(rgb_frame, cv2.COLOR_RGB2BGR)
        try:
            drawing_utils.draw_landmarks(
                bgr_frame,
                results.face_landmarks,
                FaceLandmarksConnections.FACE_LANDMARKS_TESSELATION,
                landmark_drawing_spec=None,
                connection_drawing_spec=drawing_styles.get_default_face_mesh_tesselation_style()
            )
            print("Successfully drew face landmarks!")
            cv2.imwrite("output_drawn.jpg", bgr_frame)
            print("Saved output_drawn.jpg")
        except Exception as e:
            import traceback
            traceback.print_exc()
else:
    print("Could not load image.")
