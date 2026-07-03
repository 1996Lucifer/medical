import sys

# 1. Remove from camera_api.py
with open("backend/routers/camera_api.py", "r") as f:
    camera_api = f.read()

ws_block = """
@router.websocket("/ws/status")
async def ws_cameras_status(websocket: WebSocket, db: Session = Depends(get_db)):
    \"\"\"WebSocket endpoint to push camera online/offline status periodically.\"\"\"
    await websocket.accept()
    try:
        while True:
            # Refresh from DB each loop in case new cameras are added
            cameras = db.query(models.Camera).all()
            tasks = [_check_rtsp(c.id, c.rtsp_url) for c in cameras]
            results = await asyncio.gather(*tasks)
            status_map = {str(cam_id): status for cam_id, status in results}
            await websocket.send_json(status_map)
            # Push updates every 15 seconds
            await asyncio.sleep(15)
    except WebSocketDisconnect:
        pass
    except Exception as e:
        print(f"[Status WS] Error: {e}")
"""

if ws_block in camera_api:
    camera_api = camera_api.replace(ws_block, "")
    with open("backend/routers/camera_api.py", "w") as f:
        f.write(camera_api)


# 2. Add to camera/routes.py
with open("backend/camera/routes.py", "r") as f:
    routes = f.read()

new_ws_block = """
@router.websocket("/cameras/ws/status")
async def ws_cameras_status(websocket: WebSocket, db: Session = Depends(get_db)):
    \"\"\"WebSocket endpoint to push camera online/offline status periodically.\"\"\"
    await websocket.accept()
    try:
        while True:
            import urllib.parse
            async def _check_rtsp(cam_id: int, url: str) -> tuple[int, bool]:
                try:
                    parsed = urllib.parse.urlparse(url)
                    host = parsed.hostname
                    port = parsed.port or 554
                    if not host:
                        return cam_id, False
                    fut = asyncio.open_connection(host, port)
                    reader, writer = await asyncio.wait_for(fut, timeout=2.0)
                    writer.close()
                    await writer.wait_closed()
                    return cam_id, True
                except Exception:
                    return cam_id, False
            
            cameras = db.query(models.Camera).all()
            tasks = [_check_rtsp(c.id, c.rtsp_url) for c in cameras]
            results = await asyncio.gather(*tasks)
            status_map = {str(cam_id): status for cam_id, status in results}
            await websocket.send_json(status_map)
            await asyncio.sleep(15)
    except WebSocketDisconnect:
        pass
    except Exception as e:
        print(f"[Status WS] Error: {e}")

"""

# Append just before REST helper endpoints if not already there
if "@router.websocket(\"/cameras/ws/status\")" not in routes:
    routes = routes.replace("# ─── REST helper endpoints (kept for compatibility) ───────────────────────────", new_ws_block + "\n# ─── REST helper endpoints (kept for compatibility) ───────────────────────────")
    with open("backend/camera/routes.py", "w") as f:
        f.write(routes)

