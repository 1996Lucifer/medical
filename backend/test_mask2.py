import cv2, os, numpy as np
from camera.vision_service_zones import VisionServiceZones
vs = VisionServiceZones()
img = cv2.imread('backend/t1.jpg')
tracked_people = [(1, [333, 210, 776, 687]), (2, [0, 229, 302, 872]), (3, [864, 2, 1260, 698]), (4, [251, 97, 473, 732])]
ppe = vs._detect_ppe_for_tracks(img, tracked_people)
print(ppe)
