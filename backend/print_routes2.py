from main import app
from fastapi.routing import APIRoute, APIWebSocketRoute

for route in app.routes:
    if isinstance(route, APIRoute):
        methods = route.methods
    elif isinstance(route, APIWebSocketRoute):
        methods = ["WS"]
    else:
        continue
    
    deps = getattr(route, "dependencies", [])
    has_oauth_router = any("OAuth2PasswordBearer" in str(d.dependency) or "get_current_user" in str(d.dependency) for d in deps)
    
    has_oauth_func = False
    if hasattr(route, "dependant") and hasattr(route.dependant, "dependencies"):
        has_oauth_func = any("OAuth2PasswordBearer" in str(d.call) or "get_current_user" in str(d.call) for d in route.dependant.dependencies)
        
    if "WS" in methods:
        print(f"{methods} {route.path} (Router Auth: {has_oauth_router}, Func Auth: {has_oauth_func})")
