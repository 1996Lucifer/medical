import cv2
import numpy as np
import os
import json
import asyncio
import camera.compliance_constants as comp_const

class ComplianceService:
    """
    Dynamic Rules Engine using local Vision AI (YOLO-PPE) instead of VLM.
    """
    def __init__(self):
        self._last_warning_time = {}

    async def evaluate_dynamic_rules(self, frame: np.ndarray, rules: list, staff_name: str, camera_name: str, has_mask: bool = False, has_gloves: bool = False) -> dict:
        """
        Evaluates rules natively based on mask and staff information.
        Maps staff names (e.g. 'Dr. Deepak') to roles and checks mapped rules.
        """
        is_violation = False
        reason = "No violation."
        warning = ""

        # 1. Unknown / Unauthorized Person Detection
        if staff_name == "Unknown":
            is_violation = True
            reason = "Unauthorized person detected."
            warning = "Warning, unauthorized person detected. Please identify yourself."
        else:
            # 2. Known Staff - Evaluate mapped rules based on role
            name_lower = staff_name.lower()
            roles = ["all staff"]
            if name_lower.startswith("dr") or name_lower.startswith("doc"):
                roles.append("doctors")
            elif name_lower.startswith("nurse"):
                roles.append("nurses")
            elif name_lower.startswith("compounder"):
                roles.append("compounders")

            applied_rules = []
            for r in rules:
                rule_text = r.rule_text.lower()
                for role in roles:
                    if rule_text.startswith(role):
                        applied_rules.append(rule_text)
                        break
            
            if not applied_rules:
                print(f"[ComplianceService] No mapped rules for {staff_name} (Roles: {roles}). Skipping compliance check.")
            else:
                # Evaluate the specific rules mapped to them
                for r_text in applied_rules:
                    if "mask" in r_text:
                        if not has_mask:
                            is_violation = True
                            reason = f"Safety rule violation: Mask not detected for {staff_name}."
                            warning = "Warning, please ensure you are wearing a mask."
                            break
                    if "glove" in r_text:
                        if has_gloves is not None and not has_gloves:
                            is_violation = True
                            reason = f"Safety rule violation: Gloves not detected for {staff_name}."
                            warning = "Warning, please ensure you are wearing gloves."
                            break
                    # Add future rule checks here (e.g., hairnets) as needed.

        result = {
            "violation": is_violation,
            "reason": reason,
            "spoken_warning": warning
        }

        # Play audio alert if violation detected
        if result.get("violation") and result.get("spoken_warning"):
            from events import set_zone_alert
            set_zone_alert(camera_name, duration_sec=comp_const.DEFAULT_ALERT_DURATION_SEC)
            
            import time
            from camera.vision_constants import WARNING_ALERT_COOLDOWN_SEC
            now = time.time()
            last_time = self._last_warning_time.get(camera_name, 0)
            
            if now - last_time > WARNING_ALERT_COOLDOWN_SEC:
                self._last_warning_time[camera_name] = now
                
                print(f"[ComplianceService] 🚨 VIOLATION DETECTED: {warning}")
                
                # Publish event for the frontend to speak
                from events import event_engine
                event_engine.publish_event(
                    event_type=comp_const.EVENT_TYPE_SPOKEN_WARNING,
                    camera_id=None,
                    camera_name=camera_name,
                    confidence=comp_const.DEFAULT_SPOKEN_CONFIDENCE,
                    details={"warning": warning}
                )

                # Attempt to speak on Camera Speaker, fallback to System Server Speaker
                from camera.audio_service import audio_service
                audio_service.speak(camera_name, warning)

        return result

# Global singleton for compliance
compliance_service = ComplianceService()
