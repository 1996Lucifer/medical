import asyncio
import websockets

async def test_ws():
    uri = "ws://127.0.0.1:8000/api/cameras/status"
    try:
        async with websockets.connect(uri) as websocket:
            print("Connected to wrong ws!")
            await asyncio.sleep(2)
    except Exception as e:
        print(f"Wrong WS Failed: {e}")

asyncio.run(test_ws())
