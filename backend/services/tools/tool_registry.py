import json
from pathlib import Path
from typing import Dict, Any

class ToolRegistry:
    """
    Registers deterministic business tools mapped to parameterized SQL templates.
    """
    def __init__(self):
        pass # Config loaded lazily

    def _load_config(self):
        config_path = Path(__file__).parent.parent.parent / 'agent_config.json'
        try:
            with open(config_path, 'r') as f:
                return json.load(f)
        except Exception as e:
            print(f"[ToolRegistry] Failed to load config: {e}")
            return {"tools": {}, "tool_routing": {}}

    def get_tool(self, tool_name: str) -> Dict[str, Any]:
        """Returns the configuration for a given tool."""
        config = self._load_config()
        return config.get("tools", {}).get(tool_name)

    def find_tool_for_intent(self, intent: str, entities: Dict[str, Any], message: str = "") -> str:
        """
        Dynamic heuristic mapping to choose a tool based on intent and extracted entities.
        """
        config = self._load_config()
        routing = config.get("tool_routing", {}).get(intent)
        
        if not routing:
            return None
            
        # Check specific rules first
        for rule in routing.get("rules", []):
            req_entity = rule.get("requires_entity")
            req_keyword = rule.get("requires_message_keyword")
            
            if req_entity and req_entity in entities:
                return rule["tool"]
                
            if req_keyword and req_keyword in message.lower():
                return rule["tool"]
                
        # Fallback to default tool if any
        return routing.get("default_tool")

tool_registry = ToolRegistry()
