import asyncio
import websockets

async def check():
    uri = "ws://127.0.0.1:8000/api/ws/camera?camera_id=1"
    try:
        async with websockets.connect(uri) as ws:
            print("Connected to camera WS")
            await asyncio.sleep(1)
            frame = await ws.recv()
            print(f"Received frame of size {len(frame)}")
    except Exception as e:
        print(f"Error: {e}")

asyncio.run(check())
