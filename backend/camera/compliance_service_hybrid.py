import cv2
import numpy as np
import os
import json
import base64
import asyncio
import camera.constants.compliance_constants as comp_const
from camera.compliance_engine import compliance_engine


class ComplianceService:
    """
    Dynamic Rules Engine — Zone-Aware Compliance Service.

    Now uses the ComplianceEngine for O(1) verification lookups
    instead of running VLM every few seconds. The VLM is only invoked
    during the Verification Zone workflow via VLMVerifier.
    """

    def __init__(self):
        self._last_warning_time = {}

    async def evaluate_dynamic_rules(
        self,
        frame: np.ndarray,
        rules: list,
        staff_name: str,
        camera_name: str,
        has_mask: bool = False,
        has_gloves: bool = False,
    ) -> dict:
        """
        Evaluates rules using the ComplianceEngine token system.
        Falls back to basic mask/glove booleans for backward compatibility.
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
            # 2. Check ComplianceEngine first (zone-based verification token)
            if compliance_engine.is_verified(staff_name):
                # Person has a valid compliance token — no violation
                return {
                    "violation": False,
                    "reason": "Verified via compliance token.",
                    "spoken_warning": "",
                }

            # 3. Known Staff - Evaluate mapped rules based on role
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
                print(
                    f"[ComplianceService] No mapped rules for {staff_name} "
                    f"(Roles: {roles}). Skipping compliance check."
                )
            else:
                missing_items = []

                # Check against compliance engine token for detailed items
                token = compliance_engine.get_token(staff_name)

                for r_text in applied_rules:
                    if "mask" in r_text:
                        # Check token first, then fall back to passed boolean
                        mask_ok = (token.has_mask if token else False) or has_mask
                        if not mask_ok:
                            if "a mask" not in missing_items:
                                missing_items.append("a mask")
                    if "glove" in r_text:
                        glove_ok = (
                            (token.has_left_glove and token.has_right_glove)
                            if token
                            else False
                        ) or has_gloves
                        if not glove_ok:
                            if "gloves" not in missing_items:
                                missing_items.append("gloves")

                if missing_items:
                    is_violation = True
                    reason = (
                        f"Safety rule violation: {' and '.join(missing_items)} "
                        f"not detected for {staff_name}."
                    )
                    warning = (
                        f"Warning, please ensure you are wearing "
                        f"{' and '.join(missing_items)}."
                    )

        result = {
            "violation": is_violation,
            "reason": reason,
            "spoken_warning": warning,
        }

        # Play audio alert if violation detected
        if result.get("violation") and result.get("spoken_warning"):
            from events import set_zone_alert

            set_zone_alert(
                camera_name, duration_sec=comp_const.DEFAULT_ALERT_DURATION_SEC
            )

            import time
            from camera.constants.vision_constants import WARNING_ALERT_COOLDOWN_SEC

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
                    details={"warning": warning},
                )

                # Attempt to speak on Camera Speaker, fallback to System Server Speaker
                from camera.audio_service import audio_service

                audio_service.speak(camera_name, warning)

        return result


# Global singleton for compliance
compliance_service = ComplianceService()
