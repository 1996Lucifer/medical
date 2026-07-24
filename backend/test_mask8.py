import cv2, os, numpy as np
from camera.vision_service_zones import VisionServiceZones
vs = VisionServiceZones()
img = cv2.imread('backend/t1.jpg')
res = vs.process_frame(img, 'test')
for ev in res[1]:
    print(f"TID: {ev['tid']}, BBox: {ev['bbox']}, Mask: {ev['has_mask']}")
