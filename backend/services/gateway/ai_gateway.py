from sqlalchemy.orm import Session
from services.gateway.workflow_engine import workflow_engine
from services.retrieval.cache_manager import cache_manager
import time

class AIGateway:
    """
    Main orchestration layer for the AI Backend.
    Contains no business logic or SQL. Wraps workflow with caching.
    """
    def handle_request(self, message: str, db: Session, session_id: str = "default", base64_img: str = None) -> str:
        # 1. Check exact match cache
        cached_response = cache_manager.get(message)
        if cached_response and not base64_img:
            print(f"[AIGateway] Cache HIT for message: {message}")
            from services.metrics.metrics import metrics_tracker
            metrics_tracker.log_interaction({
                "intent": "CACHE_HIT",
                "strategy": "CACHE",
                "tool_name": None,
                "model": None,
                "latency": 0.0
            })
            return cached_response
            
        # 2. Execute normal workflow if cache miss
        response = workflow_engine.execute_workflow(message, db, session_id, base64_img)
        
        # 3. Cache the successful LLM response (skip caching images for simplicity)
        if not base64_img:
            cache_manager.set(message, response)
        return response

ai_gateway = AIGateway()
