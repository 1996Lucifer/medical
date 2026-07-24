import cv2, os, numpy as np
from ultralytics import YOLO
img = cv2.imread('backend/t1.jpg')
model_path = '/Users/dj/Projects/medical_agent/backend/models/best_openvino_model'
yolo_track = YOLO(model_path, task='detect')
yolo_detect = YOLO(model_path, task='detect')

# Run tracking with classes=[0] on instance 1
track_res = yolo_track.track(img, persist=True, tracker="bytetrack.yaml", conf=0.40, classes=[0], imgsz=416, verbose=False)
# Immediately run detection with classes=None on instance 2
det_res = yolo_detect(img, conf=0.10, imgsz=416, verbose=False)
boxes = det_res[0].boxes
print("Boxes on separate instance:")
for b in boxes:
    print(f"Class: {yolo_detect.names[int(b.cls[0])]}, Conf: {float(b.conf[0]):.4f}")
