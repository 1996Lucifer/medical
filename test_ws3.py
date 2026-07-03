import asyncio
import websockets

async def test_ws():
    uri = "ws://127.0.0.1:8000/api/ws/camera?camera_id=1"
    try:
        async with websockets.connect(uri) as websocket:
            print("Connected to camera ws!")
            await asyncio.sleep(2)
    except Exception as e:
        print(f"Camera WS Failed: {e}")

asyncio.run(test_ws())
