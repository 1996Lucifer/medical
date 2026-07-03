import asyncio
import websockets
import json

async def test_ws():
    uri = "ws://127.0.0.1:8000/api/ws/camera?camera_id=1"
    try:
        print(f"Connecting to {uri}")
        async with websockets.connect(uri) as websocket:
            print("Connected!")
            # Keep reading frames
            for i in range(5):
                frame = await websocket.recv()
                print(f"Received frame of size {len(frame)}")
    except Exception as e:
        print(f"Failed: {e}")

asyncio.run(test_ws())
