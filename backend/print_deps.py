from main import app
from fastapi.routing import APIWebSocketRoute

def check_oauth(dependant):
    if not dependant:
        return False
    if dependant.call and ("OAuth2PasswordBearer" in str(dependant.call) or "get_current_user" in str(dependant.call)):
        return True
    for sub in dependant.dependencies:
        if check_oauth(sub):
            return True
    return False

for route in app.routes:
    if isinstance(route, APIWebSocketRoute):
        has_oauth = False
        # Check router-level deps
        for d in getattr(route, "dependencies", []):
            if "OAuth2PasswordBearer" in str(d.dependency) or "get_current_user" in str(d.dependency):
                has_oauth = True
        
        # Check function-level deps recursively
        if hasattr(route, "dependant") and check_oauth(route.dependant):
            has_oauth = True
            
        print(f"WS Route: {route.path} -> Has OAuth recursively? {has_oauth}")

