import asyncio
import websockets

async def test_ws():
    uri = "ws://127.0.0.1:8000/api/invalid_websocket"
    try:
        async with websockets.connect(uri) as websocket:
            print("Connected to invalid ws!")
            await asyncio.sleep(2)
    except Exception as e:
        print(f"Invalid WS Failed: {e}")

asyncio.run(test_ws())
