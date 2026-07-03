from main import app
from starlette.routing import WebSocketRoute, Mount
from fastapi.routing import APIWebSocketRoute

def print_ws(routes, prefix=""):
    for route in routes:
        if isinstance(route, Mount):
            print_ws(route.routes, prefix + route.path)
        elif isinstance(route, WebSocketRoute) or getattr(route, "methods", None) == ["WS"] or isinstance(route, APIWebSocketRoute):
            print(f"WS Route found: {prefix}{route.path} (Class: {route.__class__.__name__})")

print_ws(app.routes)
