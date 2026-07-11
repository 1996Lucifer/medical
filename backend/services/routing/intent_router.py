import os
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
    Routes user requests into deterministic intent categories.
    Uses DistilBERT/MiniLM with keyword fallback.
    """
    def __init__(self):
        self.classifier = None

    def _load_model(self):
        if self.classifier is None:
            try:
                from transformers import pipeline
                print("[IntentRouter] Loading routing model...")
                hf_token = os.environ.get("HF_TOKEN")
                self.classifier = pipeline(
                    "zero-shot-classification", 
                    model="typeform/distilbert-base-uncased-mnli",
                    token=hf_token
                )
            except ImportError:
                print("[IntentRouter] 'transformers' not found. Using keyword fallback.")
                self.classifier = "fallback"

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
        
        # 1. Fast Keyword Heuristics
        for intent, config in intents_config.items():
            keywords = config.get("keywords", [])
            if any(k in message_lower for k in keywords):
                return intent
            
        self._load_model()
        
        if self.classifier == "fallback":
            return "GENERAL"
            
        try:
            label_map = {
                config.get("zero_shot_label"): intent 
                for intent, config in intents_config.items() 
                if config.get("zero_shot_label")
            }
            labels = list(label_map.keys())
            result = self.classifier(message, candidate_labels=labels)
            
            top_label = result['labels'][0]
            return label_map[top_label]
            
        except Exception as e:
            print(f"[IntentRouter] Model error: {e}. Falling back to GENERAL.")
            return "GENERAL"

intent_router = IntentRouter()
