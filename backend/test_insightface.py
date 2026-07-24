import cv2
from camera.model_manager import ModelManager
import numpy as np

img = np.zeros((480, 640, 3), dtype=np.uint8)
app = ModelManager().get_face_analysis()
try:
    faces = app.get(img)
    print("Faces found:", len(faces))
except Exception as e:
    print("Error:", e)
