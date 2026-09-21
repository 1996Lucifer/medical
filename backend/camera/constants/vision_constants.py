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
REJECTION_THRESHOLD = 0.5
# The single highest-scoring gallery row wins via np.argmax with NO check on
# how much better it was than the runner-up - so with a small gallery (as
# few as 2-4 people), two candidates that both score "plausible but not
# great" under poor live conditions (dim light, side angle, glasses glare)
# can be nearly tied, and whichever one is numerically a hair ahead gets
# confidently displayed as a match. Confirmed live (/investigate
# 2026-09-20, same incident as INSTANT_CONFIRM_THRESHOLD above): the two
# enrolled identities' AVERAGED gallery embeddings are themselves highly
# separated (cosine similarity 0.029 - enrollment quality was not the
# problem), yet the SAME live track kept winning the argmax for the WRONG
# person at 0.55-0.78 over multiple independent re-embeds, because that
# person's own true match was apparently scoring similarly low under the
# same bad lighting - a close, ambiguous call the raw threshold alone
# can't detect. Requiring the winner to beat the runner-up by this margin
# rejects exactly that "too close to call" case as Unknown instead of
# confidently picking whichever side won by a sliver.
MIN_MATCH_MARGIN = 0.08
# Higher than REJECTION_THRESHOLD on purpose: the periocular (eyes/eyebrows
# only) crop this compares is a strictly weaker signal than a full face -
# confirmed live (/investigate 2026-09-15), two different real people scored
# 0.5 and 0.62 against the same identity's upper-face embedding, well above
# the old 0.5 bar. Defense-in-depth alongside the >=2-real-candidates gate
# at the call site (vision_service_zones.py) - that gate stops the
# degenerate single-candidate case, this threshold reduces false accepts
# once there IS real competition to discriminate against.
UPPER_FACE_REJECTION_THRESHOLD = 0.65
UPPER_FACE_HEIGHT_RATIO = 0.48
MIN_FACE_SIZE = 60
IDENTITY_REFRESH_FRAMES = 25
UNKNOWN_IDENTITY_RETRY_FRAMES = 15
IDENTITY_CACHE_TTL_FRAMES = 90
# A track must match the same staff identity this many consecutive frames
# before that identity is actually displayed/used - stops one blurry or
# unlucky frame from flipping a track's label (e.g. two different people
# both crossing the rejection threshold against the same identity).
IDENTITY_CONFIRMATION_STREAK = 3
# A single-frame match at or above this score skips the streak and confirms
# immediately. Needed because the crude centroid tracker hands out a brand
# new track_id on almost any brief occlusion/movement/angle change - without
# this, re-acquiring the SAME already-known person after a routine track
# handoff would still show a few frames of "Unknown" before re-locking, even
# though the very first check was already near-certain. Kept well above
# REJECTION_THRESHOLD so a genuinely ambiguous cross-person match (the kind
# the streak exists to catch) can't hit this bar by chance.
#
# Raised from 0.65 to 0.85 after a confirmed live false-accept
# (/investigate 2026-09-20): with only 4 staff enrolled, a single poorly-lit,
# side-angle frame of Dr. Deepak scored 0.69 against a DIFFERENT enrolled
# person's ("Anamika") gallery embedding - well above the old 0.65 bar - and
# that ONE frame instantly bypassed the entire IDENTITY_CONFIRMATION_STREAK
# safety net, writing real Attendance/ZoneTransition rows for the wrong
# person while only Dr. Deepak was physically in frame (confirmed via DB:
# the same camera/track alternated between both names within seconds).
# Dr. Deepak's own genuine matches under the same poor conditions only
# scored 0.55-0.57 that session - well below even the old bar - so he was
# never using this fast path anyway; raising it has no effect on his UX and
# forces exactly this kind of marginal, small-gallery false-accept through
# the 3-frame streak instead, where test_confirmed_track_corrects_when_a_
# different_person_takes_over already proves a wrong candidate gets
# corrected rather than committed to the event stream. A genuine same-person
# re-acquire (the case this constant exists for) typically scores 0.9+.
INSTANT_CONFIRM_THRESHOLD = 0.85
# How many consecutive checked-frames a track can score "no match at all"
# before it's treated as a genuine stranger and backed off to the slow
# UNKNOWN_IDENTITY_RETRY_FRAMES interval. A moving person's face is
# frequently motion-blurred enough to score below REJECTION_THRESHOLD on
# any single frame even though they're a known staff member - without this
# grace period, one blurry frame (near-guaranteed while walking/turning)
# immediately gets a track written off as "probably a stranger" and only
# rechecked every 15 frames, by which point the crude centroid tracker has
# often already churned to a new track_id anyway - the person can end up
# stuck displaying "Unknown" for as long as they keep moving. This gives
# several fast (every-frame) attempts first, so a clear frame in between
# blurry ones gets a chance to confirm quickly. Set to roughly 1-2 seconds
# of continuous movement (at typical dispatch rates) rather than a handful
# of frames - real walking/turning motion can stay blurry for longer than
# a few hundred milliseconds before a clear-enough angle comes along.
NO_MATCH_RETRY_GRACE_FRAMES = 30

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
