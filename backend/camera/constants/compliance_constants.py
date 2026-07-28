"""
compliance_constants.py
This file contains constants related to the AI compliance checking engine.
It includes event definitions, VLM prompt templates, and default thresholds 
for managing hospital rules and security alerts.
"""

# ==========================================
# General Event Types
# ==========================================
EVENT_TYPE_SPOKEN_WARNING = "SpokenWarning"           # Broadcasted when a spoken audio alert is dispatched

# ==========================================
# Default Configurations
# ==========================================
DEFAULT_ALERT_DURATION_SEC = 5.0                      # Default duration to keep an alert active locally
DEFAULT_SPOKEN_CONFIDENCE = 1.0                       # Default confidence assigned to VLM-generated spoken warnings

# ==========================================
# VLM (Vision-Language Model) Prompt Templates
# ==========================================
# This prompt is passed to the VLM (e.g. MedGemma) to evaluate if a person in the frame 
# violates any of the dynamic user-defined security rules.
COMPLIANCE_SYSTEM_PROMPT = """
You are an AI Security and Compliance Monitor for a hospital camera feed.
Camera Location: {camera_name}
Person Identified: {staff_name}

Here are the strict compliance rules for this area:
{rules_text}

Analyze the provided camera frame. Is the person in the frame violating ANY of the rules above?
Pay special attention to medical masks, face coverings, and medical gloves (blue, white, or nitrile) if a rule mentions them.
If the Person Identified is 'Unknown', determine if they appear to be medical staff (e.g., wearing scrubs, lab coat, stethoscope, or medical mask). If they appear to be medical staff, do not treat them as an unauthorized intruder unless a specific rule is violated.

Respond strictly in JSON format matching this schema:
{{
    "violation": boolean,
    "reason": "String explaining the violation if true, or empty if false",
    "spoken_warning": "A short 1-sentence verbal warning to be spoken out loud by the camera speaker. Personalize it with the person's name if they are violating."
}}
"""

# ==========================================
# Zone-Based Verification & Security Events
# ==========================================
EVENT_TYPE_VERIFICATION_STARTED = "VerificationStarted" # Triggered when a person steps into a verification zone
EVENT_TYPE_VERIFICATION_PASSED = "VerificationPassed"   # Triggered when VLM confirms PPE compliance
EVENT_TYPE_VERIFICATION_FAILED = "VerificationFailed"   # Triggered when VLM identifies missing PPE
EVENT_TYPE_VERIFICATION_EXPIRED = "VerificationExpired" # Triggered when a verified person stays in restricted zone too long
EVENT_TYPE_MASK_REMOVED = "MaskRemoved"                 # Triggered when a verified person removes mask in restricted zone
EVENT_TYPE_UNAUTHORIZED_ENTRY = "UnauthorizedEntry"     # Triggered when an unknown person enters a restricted zone
