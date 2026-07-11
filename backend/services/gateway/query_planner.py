from typing import Dict, Any
from services.tools.tool_registry import tool_registry

class QueryPlanner:
    """
    Determines the retrieval strategy (SQL, Vector, Hybrid, Direct LLM).
    """
    def plan_query(self, intent: str, entities: Dict[str, Any], message: str) -> str:
        """
        Returns the chosen strategy: 'SQL', 'VECTOR', 'HYBRID', 'LLM'
        """
        # Temporary heuristic: if intent is PATIENT but they explicitly asked for a report
        if intent == "PATIENT" and "report" in message.lower():
            intent = "MEDICAL_REPORT"
            
        # 1. Try to find an exact SQL tool match
        tool_name = tool_registry.find_tool_for_intent(intent, entities, message)
        if tool_name:
            return "SQL", tool_name

        # 2. General intents go straight to LLM or Vector
        if intent in ["GENERAL", "ADMIN"]:
            return "LLM", None
            
        # 3. Fallback to Vector Search
        return "VECTOR", None

query_planner = QueryPlanner()
