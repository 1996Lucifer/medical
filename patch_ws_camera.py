import re

with open('backend/camera/routes.py', 'r') as f:
    content = f.read()

replacement = """
    # Pre-compute a loading frame
    import cv2
    import numpy as np
    loading_img = np.zeros((480, 640, 3), dtype=np.uint8)
    cv2.putText(loading_img, "Connecting to camera...", (50, 240), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (255, 255, 255), 2)
    _, loading_buf = cv2.imencode(".jpg", loading_img)
    loading_frame_bytes = loading_buf.tobytes()

    try:
        while True:
            try:
                frame = await asyncio.wait_for(queue.get(), timeout=2.0)
                await websocket.send_bytes(frame)
            except asyncio.TimeoutError:
                # Send loading frame to keep connection alive and show feedback
                await websocket.send_bytes(loading_frame_bytes)
    except WebSocketDisconnect:
"""

content = re.sub(
    r"    try:\n        while True:\n            frame = await asyncio.wait_for\(queue.get\(\), timeout=60.0\)\n            await websocket.send_bytes\(frame\)\n    except WebSocketDisconnect:",
    replacement,
    content
)

with open('backend/camera/routes.py', 'w') as f:
    f.write(content)
