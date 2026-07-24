import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

base_options = python.BaseOptions(model_asset_path='models/holistic_landmarker.task')
options = vision.HolisticLandmarkerOptions(base_options=base_options)
detector = vision.HolisticLandmarker.create_from_options(options)

import inspect
print(inspect.signature(vision.HolisticLandmarkerResult))
from typing import get_type_hints
print(get_type_hints(vision.HolisticLandmarkerResult))
