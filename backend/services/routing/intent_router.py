import json
from pathlib import Path

INTENT_CATEGORIES = [
    "PATIENT",
    "CONSULTATION",
    "MEDICAL_REPORT",
    "ATTENDANCE",
    "EQUIPMENT",
    "CAMERA",
    "SECURITY",
    "ADMIN",
    "GENERAL"
]

class IntentRouter:
    """
    Routes user requests into deterministic intent categories using pure
    keyword matching against agent_config.json.

    Deliberately has no ML model in this path (no zero-shot classifier, no
    embedding model): anything that needs a downloaded/cached model is a
    liability in an offline or read-only-filesystem deployment, and it was
    also the source of a real misrouting bug (a bare "hello" was classified
    as CONSULTATION by a poorly-calibrated zero-shot model). Any message
    that doesn't match a clinical/domain keyword falls through to GENERAL,
    which routes to Qwen3 - only PATIENT/CONSULTATION/MEDICAL_REPORT route
    to MedGemma (see services/routing/llm_router.py).
    """
    def _load_config(self):
        config_path = Path(__file__).parent.parent.parent / 'agent_config.json'
        try:
            with open(config_path, 'r') as f:
                return json.load(f).get('intents', {})
        except Exception as e:
            print(f"[IntentRouter] Failed to load config: {e}")
            return {}

    def detect_intent(self, message: str) -> str:
        intents_config = self._load_config()
        message_lower = message.lower()

        for intent, config in intents_config.items():
            keywords = config.get("keywords", [])
            if any(k in message_lower for k in keywords):
                return intent

        return "GENERAL"

intent_router = IntentRouter()
