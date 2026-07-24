import cv2, os, numpy as np
from camera.vision_service_zones import VisionServiceZones
vs = VisionServiceZones()
img = cv2.imread('backend/t1.jpg')
res = vs.process_frame(img, 'test')

for box in vs._last_ppe_boxes:
    if box['class'] == 'mask':
        print(f"Mask BBox: {box['bbox']}")

for tid, cache in vs.identity_cache.items():
    if 'face_bbox' in cache:
        print(f"TID {tid} Face BBox: {cache['face_bbox']}")
        
