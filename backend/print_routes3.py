from main import app
from fastapi.routing import APIWebSocketRoute

for route in app.routes:
    if isinstance(route, APIWebSocketRoute):
        print(f"Route: {route.path}")
        print(f"Router deps: {route.dependencies}")
        print(f"Func deps: {[d.call for d in route.dependant.dependencies]}")
        print("---")
