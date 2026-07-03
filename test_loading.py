import cv2
import numpy as np

loading_img = np.zeros((480, 640, 3), dtype=np.uint8)
cv2.putText(loading_img, "Connecting to camera...", (50, 240), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (255, 255, 255), 2)
_, loading_buf = cv2.imencode(".jpg", loading_img)
loading_frame_bytes = loading_buf.tobytes()
print(f"Bytes len: {len(loading_frame_bytes)}")
