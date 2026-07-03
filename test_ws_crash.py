import asyncio
import websockets

async def test_ws():
    # simulate the four websockets
    uris = [
        "ws://127.0.0.1:8000/api/ws/camera?camera_id=1",
        "ws://127.0.0.1:8000/api/cameras/ws/status",
        "ws://127.0.0.1:8000/api/security/ws/alerts",
        "ws://127.0.0.1:8000/api/events/ws"
    ]
    for uri in uris:
        try:
            print(f"Connecting to {uri}")
            async with websockets.connect(uri) as websocket:
                print(f"Connected!")
                await asyncio.sleep(0.5)
        except Exception as e:
            print(f"Failed: {e}")

asyncio.run(test_ws())
