import asyncio
import websockets
import sys
import psycopg2
import cv2

def get_staff_id():
    conn = psycopg2.connect("postgresql://localhost/medical_agent")
    cur = conn.cursor()
    cur.execute("SELECT id FROM staff LIMIT 1;")
    res = cur.fetchone()
    conn.close()
    return res[0] if res else None

async def test_ws():
    staff_id = get_staff_id()
    uri = f"ws://127.0.0.1:8000/api/staff/{staff_id}/live_setup/ws"
    try:
        async with websockets.connect(uri) as websocket:
            response = await websocket.recv()
            
            with open("t1.jpg", "rb") as f:
                img_bytes = f.read()
            await websocket.send(img_bytes)
            
            response = await websocket.recv()
            print("Received after frame:", response)
    except Exception as e:
        print("Exception:", e)

asyncio.run(test_ws())
