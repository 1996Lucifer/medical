import cv2, os, numpy as np
from camera.vision_service_zones import VisionServiceZones
from camera.model_manager import ModelManager
vs = VisionServiceZones()
img = cv2.imread('backend/t1.jpg')

# Patch the detector to artificially shift mask detections down by 35 pixels
orig_detector = ModelManager().get_ppe_detector()

class PatchedDetector:
    def __init__(self, orig):
        self.orig = orig
        self.names = orig.names
        
    def __call__(self, frame, conf, imgsz, verbose):
        res = self.orig(frame, conf=conf, imgsz=imgsz, verbose=verbose)
        for b in res[0].boxes:
            if self.names[int(b.cls[0])] == 'mask':
                b.xyxy[0][1] += 35 # Shift y1 down
                b.xyxy[0][3] += 35 # Shift y2 down
        return res
        
# Force identity cache for TID 4 (since we are testing frame 1, process_frame hasn't populated it yet)
# We will just run process_frame with the patched detector!
vs._detect_ppe_for_tracks_orig = vs._detect_ppe_for_tracks

def patched_detect_ppe(frame, tracks):
    # Temporarily override detector
    ModelManager()._ppe_detector = PatchedDetector(ModelManager().get_ppe_detector())
    res = vs._detect_ppe_for_tracks_orig(frame, tracks)
    ModelManager()._ppe_detector = orig_detector # Restore
    return res

vs._detect_ppe_for_tracks = patched_detect_ppe

# We need to run it twice. First frame to populate identity cache (with face bbox),
# Second frame to use the cache and apply the logic on the shifted mask!
res1 = vs.process_frame(img, 'test')
res2 = vs.process_frame(img, 'test')

for ev in res2[1]:
    if ev['tid'] == 4:
        print(f"TID: {ev['tid']}, Mask: {ev['has_mask']}")
        
