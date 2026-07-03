import asyncio
import websockets

async def test_ws():
    uri = "ws://127.0.0.1:8000/api/cameras/ws/status"
    try:
        async with websockets.connect(uri) as websocket:
            print("Connected to status ws!")
            response = await websocket.recv()
            print(f"Received: {response}")
    except Exception as e:
        print(f"Status WS Failed: {e}")

asyncio.run(test_ws())
