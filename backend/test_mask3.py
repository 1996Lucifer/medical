import cv2, os, numpy as np
from camera.vision_service_zones import VisionServiceZones
vs = VisionServiceZones()
img = cv2.imread('backend/t1.jpg')

# Patch process_frame to print intermediate states
orig_detect = vs._detect_ppe_for_tracks
def patched_detect(frame, tracks):
    res = orig_detect(frame, tracks)
    print("DETECTOR RETURN:", res)
    return res
vs._detect_ppe_for_tracks = patched_detect

res = vs.process_frame(img, 'test')
print("FINAL EVENTS:", [(ev['tid'], ev['has_mask']) for ev in res[1]])
