from main import app
for route in app.routes:
    if hasattr(route, "methods"):
        methods = route.methods
    else:
        methods = ["WS"]
    
    deps = getattr(route, "dependencies", [])
    has_oauth = any("OAuth2PasswordBearer" in str(d.dependency) or "get_current_user" in str(d.dependency) for d in deps)
    print(f"{methods} {route.path} (Has OAuth: {has_oauth})")
