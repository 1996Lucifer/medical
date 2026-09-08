"""
vision_constants.py
This file defines the configuration constants for the AI Vision Engine,
including model paths, hardware backend settings, confidence thresholds,
and logic-timing constants (like cooldowns and cache TTLs).
"""

# ==========================================
# Vision Compute Backend Settings
# These profiles define the resolution, target framerate, and engine backend
# based on the underlying hardware (NVIDIA GPU, Apple Silicon, or CPU).
# ==========================================
CUDA_CONFIG = {
    "backend": "cuda",
    "ctx_id": 0,
    "det_size": (640, 640),
    "frame_width": 1280,
    "jpeg_quality": 85,
    "target_fps": 25,
    "label": "CUDA GPU",
    # Send every 2nd captured frame to inference; PPE runs on every dispatched frame.
    "ai_sample_interval": 2,
    "ppe_interval": 1,
}

COREML_CONFIG = {
    "backend": "coreml",
    "ctx_id": 0,
    "det_size": (640, 640),
    "frame_width": 1920,
    "jpeg_quality": 90,
    "target_fps": 20,
    "label": "Apple CoreML",
    "ai_sample_interval": 3,
    "ppe_interval": 1,
}

CPU_CONFIG = {
    "backend": "cpu",
    "ctx_id": -1,
    "det_size": (320, 320),
    "frame_width": 640,
    "jpeg_quality": 75,
    "target_fps": 15,
    "label": "CPU (OpenVINO)",
    # CPU is the most starved profile: sample less often and run PPE on
    # every other dispatched frame (the 60-frame evidence/revocation TTLs
    # comfortably tolerate this).
    "ai_sample_interval": 5,
    "ppe_interval": 2,
}


def get_runtime_vision_config(available_providers=None):
    """
    Pick runtime settings for the active inference backend.
    Automatically enables GPU high-performance profile if CUDA or Apple Silicon (MPS/CoreML) is detected.
    """
    try:
        import torch

        if torch.cuda.is_available():
            return CUDA_CONFIG
        if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            return COREML_CONFIG
    except Exception:
        pass

    if available_providers is None:
        try:
            import onnxruntime as ort

            available_providers = ort.get_available_providers()
        except Exception:
            available_providers = []

    if "CUDAExecutionProvider" in available_providers:
        return CUDA_CONFIG
    if "CoreMLExecutionProvider" in available_providers:
        return COREML_CONFIG

    return CPU_CONFIG


# ==========================================
# Facial Recognition & Tracking
# Thresholds and cache timers for identifying staff and tracking Unknowns.
# ==========================================
REJECTION_THRESHOLD = 0.35
UPPER_FACE_REJECTION_THRESHOLD = 0.38
UPPER_FACE_HEIGHT_RATIO = 0.48
MIN_FACE_SIZE = 60
IDENTITY_REFRESH_FRAMES = 25
UNKNOWN_IDENTITY_RETRY_FRAMES = 15
IDENTITY_CACHE_TTL_FRAMES = 90

# ==========================================
# Security Alerts & Cooldowns
# Wait times (in seconds) between triggering similar events to prevent spam.
# ==========================================
UNKNOWN_PERSON_GRACE_PERIOD_SEC = 3.0
TAMPER_ALERT_COOLDOWN_SEC = 10.0
WARNING_ALERT_COOLDOWN_SEC = 60.0
EMERGENCY_ALERT_COOLDOWN_SEC = 15.0

# ==========================================
# Camera Tamper Detection
# Statistical thresholds for detecting when a camera is covered or blinded.
# ==========================================
TAMPER_STD_THRESHOLD = 35.0
TAMPER_MEAN_THRESHOLD = 20.0
TAMPER_LAPLACIAN_THRESHOLD = 50.0

# ==========================================
# Visualization & Drawing
# Master toggles for drawing debugging info like the skeletal pose.
# ==========================================
DRAW_POSE_SKELETON = True

# ==========================================
# Zone-Based Compliance & VLM Prompts
# Configurations for the localized Verification and Restricted zones, including
# the exact natural language prompts fed to the VLM (MedGemma) to verify PPE.
# ==========================================
VERIFICATION_EXPIRY_SEC = 120  # 2 minutes
VERIFICATION_CONFIDENCE_THRESHOLD = 0.7
# VLM Prompts for PPE Verification
VLM_MASK_PROMPT = "Look closely at the face. Is there a blue or white surgical mask clearly covering the nose and mouth? If the face is bare, answer NO. Answer only YES or NO."
VLM_GLOVE_PROMPT = "Look closely at the hands. Are there blue, white, or nitrile medical examination gloves covering the hands? If the hands are bare skin, or if you cannot see hands, answer NO. Answer only YES or NO."

# ==========================================
# YOLO Object Detection (Person & Equipment)
# Settings for the primary object detectors including image size, confidence,
# and temporal persistence filters.
# ==========================================
YOLO_MODEL = "yolo11n.onnx"
YOLO_CONFIDENCE_THRESHOLD = 0.65
YOLO_PERSON_CLASS = 0  # COCO class ID for 'person'
YOLO_CPU_IMGSZ = 416
YOLO_GPU_IMGSZ = 640
# Reject implausibly thin or wide "person" boxes (common chair/door-edge false positives).
MIN_PERSON_ASPECT_RATIO = 0.20
MIN_PERSON_HEIGHT_PX = 100
PPE_YOLO_MODEL = "best.onnx"
PPE_YOLO_FP16_MODEL = "best.fp16.onnx"
PPE_YOLO_OPENVINO_DIR = "openvino"
# Auto-enable the OpenVINO PPE export on CPU-backed deployments (where it
# exists) instead of always falling back to the slower plain ONNX model.
USE_OPENVINO_PPE_MODEL = get_runtime_vision_config()["backend"] == "cpu"
PPE_DETECTION_INTERVAL_FRAMES = 1
# 0.50 let single-frame coin-flip detections (e.g. "mask 51%" on a bare face)
# through, immediately granting up to PPE_EVIDENCE_TTL_FRAMES of false
# "present" evidence off ONE noisy frame. Raised to filter those out at the
# source; PPE_CONFIRMATION_STREAK below adds a second, independent guard.
PPE_DETECTION_CONFIDENCE_THRESHOLD = 0.65
PPE_EVIDENCE_TTL_FRAMES = 60
# Revocation (below) already requires 60 consecutive MISSES before dropping a
# confirmed item — a deliberate false-negative safety margin. But
# acquisition had no equivalent guard: a single positive frame was enough to
# mark an item present for the full TTL window. This requires a short streak
# of consecutive positive detections before counting an item as present,
# closing that asymmetry.
PPE_CONFIRMATION_STREAK = 3
# Three detector passes are about 1.5s at the CPU profile; use a longer window
# because hands can leave the frame while staff are moving naturally.
PPE_REVOCATION_MISSED_SAMPLES = 60

# ==========================================
# Zone Processing Types
# Enum-like constants for different area designations in the hospital layout.
# ==========================================
ZONE_TYPE_OBSERVATION = "observation"
ZONE_TYPE_VERIFICATION = "verification"
ZONE_TYPE_RESTRICTED = "restricted"
