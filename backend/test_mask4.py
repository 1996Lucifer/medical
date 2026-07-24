import cv2, os, numpy as np
from camera.model_manager import ModelManager
img = cv2.imread('backend/t1.jpg')
yolo = ModelManager().get_yolo_detector()
# Run tracking
track_res = yolo.track(img, persist=True, tracker="bytetrack.yaml", conf=0.40, classes=[0], imgsz=416, verbose=False)
# Immediately run detection
det_res = yolo(img, conf=0.10, imgsz=416, verbose=False)
boxes = det_res[0].boxes
print("Boxes after tracking:")
for b in boxes:
    print(f"Class: {yolo.names[int(b.cls[0])]}, Conf: {float(b.conf[0]):.4f}")
