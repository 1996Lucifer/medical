import cv2
from camera.model_manager import ModelManager
import numpy as np

img = np.zeros((480, 640, 3), dtype=np.uint8)
# Add a white square to simulate something
cv2.rectangle(img, (200, 200), (400, 400), (255, 255, 255), -1)

app = ModelManager().get_face_analysis({"ctx_id": -1, "det_size": (640, 640)})
try:
    faces = app.get(img)
    print("Faces found (with config):", len(faces))
except Exception as e:
    print("Error (with config):", e)
