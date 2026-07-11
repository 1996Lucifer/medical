# Constants for Vision Service and Camera Worker

# --- Vision Compute Backend Settings ---
CUDA_CONFIG = {
    "backend": "cuda",
    "ctx_id": 0,
    "det_size": (640, 640),
    "frame_width": 1280,
    "jpeg_quality": 85,
    "target_fps": 25,
    "label": "CUDA GPU",
}

COREML_CONFIG = {
    "backend": "coreml",
    "ctx_id": 0,
    "det_size": (640, 640),
    "frame_width": 1920,
    "jpeg_quality": 90,
    "target_fps": 20,
    "label": "Apple CoreML",
}

CPU_CONFIG = {
    "backend": "cpu",
    "ctx_id": -1,
    "det_size": (320, 320),
    "frame_width": 640,
    "jpeg_quality": 75,
    "target_fps": 10,
    "label": "CPU",
}

# --- Facial Recognition ---
REJECTION_THRESHOLD = 0.5
MIN_FACE_SIZE = 60

# --- Security Alerts ---
UNKNOWN_PERSON_GRACE_PERIOD_SEC = 3.0
TAMPER_ALERT_COOLDOWN_SEC = 10.0
WARNING_ALERT_COOLDOWN_SEC = 10.0
EMERGENCY_ALERT_COOLDOWN_SEC = 15.0

# --- Tamper Detection ---
TAMPER_STD_THRESHOLD = 35.0
TAMPER_MEAN_THRESHOLD = 20.0
TAMPER_LAPLACIAN_THRESHOLD = 50.0

# --- Visualization ---
DRAW_POSE_SKELETON = True

