import cv2
import numpy as np
import os
import json
import base64
import asyncio
import camera.constants.compliance_constants as comp_const
from services.llm_manager import llm_manager

class ComplianceService:
    """
    Dynamic Rules Engine using Background VLM (MedGemma) reasoning.
    """
    def __init__(self):
        self._last_warning_time = {}
        self._vlm_active = set()

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
                missing_items = []
                
                # Check if we need PPE evaluation
                needs_ppe_eval = any("mask" in r_text or "glove" in r_text for r_text in applied_rules)
                
                if needs_ppe_eval:
                    # [VLM CHECK DISABLED] 
                    # We are using pixel-perfect OpenCV Color + Pose tracking instead.
                    pass
                    '''
                    # Prevent overlapping VLM checks for the same person to avoid memory explosion!
                    if staff_name in self._vlm_active:
                        print(f"[ComplianceService] VLM already analyzing {staff_name}. Skipping to prevent lag.")
                    else:
                        self._vlm_active.add(staff_name)
                        try:
                            # Use VLM for robust PPE detection
                            _, buffer = cv2.imencode('.jpg', frame)
                            base64_img = base64.b64encode(buffer).decode('utf-8')
                            
                            prompt = (
                                "Analyze this image of a hospital staff member. "
                                "Determine if they are wearing a medical mask covering their mouth/nose, "
                                "and if their hands have surgical gloves on. "
                                "Reply ONLY with a valid JSON object in this format: "
                                '{"has_mask": true, "has_gloves": false}'
                            )
                            
                            loop = asyncio.get_running_loop()
                            vlm_response = await loop.run_in_executor(None, llm_manager.generate_with_image, base64_img, prompt, True)
                            clean_json = vlm_response.replace('```json', '').replace('```', '').strip()
                            data = json.loads(clean_json)
                            # VLM is the ground truth, override the crude OpenCV logic
                            has_mask = data.get("has_mask", has_mask)
                            has_gloves = data.get("has_gloves", has_gloves)
                            print(f"[ComplianceService] VLM PPE Check for {staff_name}: Mask={has_mask}, Gloves={has_gloves}")
                        except Exception as e:
                            print(f"[ComplianceService] VLM PPE Check Failed: {e}. Falling back to OpenCV.")
                        finally:
                            self._vlm_active.discard(staff_name)
                    '''

                # Evaluate the specific rules mapped to them
                for r_text in applied_rules:
                    if "mask" in r_text:
                        if not has_mask:
                            if "a mask" not in missing_items:
                                missing_items.append("a mask")
                    if "glove" in r_text:
                        if has_gloves is not None and not has_gloves:
                            if "gloves" not in missing_items:
                                missing_items.append("gloves")
                    # Add future rule checks here (e.g., hairnets) as needed.
                    
                if missing_items:
                    is_violation = True
                    reason = f"Safety rule violation: {' and '.join(missing_items)} not detected for {staff_name}."
                    warning = f"Warning, please ensure you are wearing {' and '.join(missing_items)}."
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
                    details={"warning": warning}
                )

                # Audio speaking disabled for PPE violations (no mask/gloves)
                # from camera.audio_service import audio_service
                # audio_service.speak(camera_name, warning)

        return result

# Global singleton for compliance
compliance_service = ComplianceService()
