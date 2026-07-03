import cv2
import numpy as np
import os
import json
import asyncio
from google import genai
from google.genai import types
from PIL import Image

class ComplianceService:
    """
    Dynamic Rules Engine using Gemini Multimodal Vision and macOS TTS.
    """
    def __init__(self):
        self.api_key = os.getenv("GEMINI_API_KEY")
        if self.api_key:
            self.client = genai.Client(api_key=self.api_key)
        else:
            self.client = None

    async def evaluate_dynamic_rules(self, frame: np.ndarray, rules: list, staff_name: str, camera_name: str) -> dict:
        """
        Sends the live camera frame to Gemini 1.5 Flash to evaluate natural language rules.
        """
        if not self.client or not rules:
            return {"violation": False, "reason": "No rules or no API key"}

        # Combine rules into a numbered string
        rules_text = "\n".join([f"{i+1}. {r.rule_text}" for i, r in enumerate(rules)])

        prompt = f"""
You are an AI Security and Compliance Monitor for a hospital camera feed.
Camera Location: {camera_name}
Person Identified: {staff_name}

Here are the strict compliance rules for this area:
{rules_text}

Analyze the provided camera frame. Is the person in the frame violating ANY of the rules above?
Pay special attention to medical gloves (blue, white, or nitrile) if a rule mentions them.
Respond strictly in JSON format matching this schema:
{{
    "violation": boolean,
    "reason": "String explaining the violation if true, or empty if false",
    "spoken_warning": "A short 1-sentence verbal warning to be spoken out loud by the camera speaker. Personalize it with the person's name if they are violating."
}}
"""
        try:
            # Convert OpenCV BGR to RGB PIL Image
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            pil_image = Image.fromarray(rgb_frame)

            response = await self.client.aio.models.generate_content(
                model='gemini-2.5-flash',
                contents=[prompt, pil_image],
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                )
            )

            result = json.loads(response.text)
            
            # Play audio alert if violation detected
            if result.get("violation") and result.get("spoken_warning"):
                warning = result["spoken_warning"].replace('"', '')
                print(f"[ComplianceService] 🚨 VIOLATION DETECTED: {warning}")
                
                from events import set_zone_alert
                set_zone_alert(camera_name, duration_sec=10.0)
                
                # Publish event for the frontend to speak
                from events import event_engine
                event_engine.publish_event(
                    event_type="SpokenWarning",
                    camera_id=None,
                    camera_name=camera_name,
                    confidence=1.0,
                    details={"warning": warning}
                )

                # Attempt to speak on Camera Speaker, fallback to System Server Speaker
                from camera.audio_service import audio_service
                audio_service.speak(camera_name, warning)

            return result
        except Exception as e:
            print(f"[ComplianceService] Gemini evaluation failed: {e}")
            return {"violation": False, "reason": str(e)}

# Global singleton for compliance
compliance_service = ComplianceService()
