import asyncio
import websockets

async def run():
    async with websockets.connect('ws://127.0.0.1:8000/api/ws/camera?camera_id=1&mode=ai') as ws:
        await asyncio.sleep(2)

asyncio.run(run())
