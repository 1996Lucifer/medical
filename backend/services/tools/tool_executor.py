from typing import Dict, Any, List
from sqlalchemy.orm import Session
from services.tools.tool_registry import tool_registry
from services.retrieval.sql_retriever import sql_retriever

class ToolExecutor:
    """
    Validates parameters and executes registered tools.
    """
    def execute_tool(self, tool_name: str, entities: Dict[str, Any], db: Session) -> List[Dict[str, Any]]:
        tool_config = tool_registry.get_tool(tool_name)
        if not tool_config:
            return []

        # Validate required parameters
        missing_params = []
        for param in tool_config["required_parameters"]:
            if param not in entities:
                missing_params.append(param)
        
        if missing_params:
            print(f"[ToolExecutor] Missing parameters for {tool_name}: {missing_params}")
            return []
            
        # Execute
        print(f"[ToolExecutor] Executing {tool_name} with parameters: {entities}")
        results = sql_retriever.execute(db, tool_config["sql_template"], entities)
        return results

tool_executor = ToolExecutor()
