from typing import Dict, Any, List, Optional
from sqlalchemy.orm import Session
from services.tools.tool_registry import tool_registry
from services.retrieval.sql_retriever import sql_retriever


class ToolAccessDenied(Exception):
    """Raised when the caller's role isn't in the tool's allowed_roles list."""
    def __init__(self, tool_name: str, role: Optional[str]):
        self.tool_name = tool_name
        self.role = role
        super().__init__(f"Role '{role}' is not permitted to use tool '{tool_name}'")


class ToolExecutor:
    """
    Validates parameters and role permissions, then executes registered tools.
    """
    def execute_tool(self, tool_name: str, entities: Dict[str, Any], db: Session, role: Optional[str] = None) -> List[Dict[str, Any]]:
        tool_config = tool_registry.get_tool(tool_name)
        if not tool_config:
            return []

        # Enforce allowed_roles (agent_config.json) - this was previously
        # declared in config but never actually checked anywhere, letting
        # any authenticated role run any tool regardless of its declared
        # allowed_roles. superadmin always bypasses, matching the RBAC
        # convention used elsewhere in the app (see has_permission()).
        allowed_roles = tool_config.get("allowed_roles")
        if allowed_roles and role != "superadmin" and role not in allowed_roles:
            print(f"[ToolExecutor] Role '{role}' denied for tool '{tool_name}' (allowed: {allowed_roles})")
            raise ToolAccessDenied(tool_name, role)

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
