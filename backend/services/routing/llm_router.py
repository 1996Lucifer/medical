class LLMRouter:
    """
    Determines which LLM should answer the query based on intent.
    Prevents the AI Gateway from being model-aware.
    """
    
    def __init__(self):
        # Map intents to the target LLM
        self.intent_to_model = {
            "PATIENT": "MedGemma",
            "CONSULTATION": "MedGemma",
            "MEDICAL_REPORT": "MedGemma",
            "ATTENDANCE": "Qwen3",
            "EQUIPMENT": "Qwen3",
            "CAMERA": "Qwen3",
            "SECURITY": "Qwen3",
            "ADMIN": "Qwen3",
            "GENERAL": "Qwen3"
        }

    def route_to_model(self, intent: str) -> str:
        """
        Returns the appropriate model name for a given intent.
        """
        return self.intent_to_model.get(intent, "Qwen3")

llm_router = LLMRouter()
