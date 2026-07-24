import cv2
from camera.model_manager import ModelManager
import numpy as np
import os

img = cv2.imread("uploads/staff/93a9324a7ee445fa9e0bb7d4fb2c3d32_front.jpg")
print("Image shape:", img.shape)

for det_size in [(160, 160), (320, 320), (640, 640), None]:
    if det_size is None:
        config = None
        print("Testing NO config")
    else:
        config = {"ctx_id": -1, "det_size": det_size}
        print(f"Testing det_size: {det_size}")
    
    # We must create a NEW app for each config to trigger prepare properly, or call prepare directly
    from insightface.app import FaceAnalysis
    app = FaceAnalysis(name="buffalo_l", root="~/.insightface")
    if config:
        app.prepare(ctx_id=config["ctx_id"], det_size=config["det_size"])
    else:
        app.prepare(ctx_id=-1)
        
    faces = app.get(img)
    print("Faces found:", len(faces))
