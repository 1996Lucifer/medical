"""
Constant strings for audio warnings, log messages, and notifications.
Centralizing these makes localization and modification easier.
"""

# ==========================================
# Audio Warning Messages
# ==========================================

# Used when an unknown person is detected in a restricted or verification zone
WARNING_UNAUTHORIZED_CAMERA = "Warning, unauthorized person detected on {camera_name}. Please identify yourself."
WARNING_UNAUTHORIZED = "Warning, unauthorized person detected. Please identify yourself."

# Used when a known person is wearing a mask improperly (e.g. on chin)
WARNING_IMPROPER_MASK = "Warning, {staff_name}, please pull your mask up to cover your nose and mouth."

# Used when a known person is missing specific PPE items
WARNING_MISSING_PPE_CAMERA = "Warning, {staff_name}, on {camera_name}, please wear {missing_text}."
WARNING_MISSING_PPE = "Warning, please ensure you are wearing {missing_text}."

# Used when a camera feed appears blocked, covered, or tampered with
WARNING_CAMERA_TAMPERED = "Alert, {camera_name} appears to be blocked or tampered with. Security has been notified."

# Used when a person hasn't completed their LLM Verification process yet
WARNING_VERIFICATION_IN_PROGRESS = "Warning, {staff_name}, on {camera_name}, PPE verification is still in progress."

# ==========================================
# Log / Internal Event Messages
# ==========================================
LOG_RESTRICTED_VIOLATION = "[Worker] 🚨 RESTRICTED ZONE VIOLATION: {staff_name} missing {missing}"
ALERT_UNAUTHORIZED_ENTRY = "Unauthorized person detected."
