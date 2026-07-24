import cv2
import time
from camera.vision_service_mediapipe import vision_service
from routers.staff import load_staff_list
from database import SessionLocal

db = SessionLocal()
staff_list = load_staff_list(db)
db.close()
print(f"Loaded {len(staff_list)} staff from DB.")
vision_service.update_staff_embeddings(staff_list)

frame = cv2.imread("uploads/staff/93a9324a7ee445fa9e0bb7d4fb2c3d32_front.jpg")
print("Processing frame...")
_, face_events, _, _, _ = vision_service.process_frame(frame)
print("Face events:", face_events)

