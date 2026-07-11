import asyncio
import os
import cv2
import socket
from urllib.parse import urlparse
import numpy as np
from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import Response
from sqlalchemy.orm import Session
from typing import Optional

from database import get_db, SessionLocal
import models
from routers.staff import load_staff_list
from camera.worker import CameraWorker, active_workers
from camera.webrtc import CameraVideoStreamTrack
from aiortc import RTCPeerConnection, RTCSessionDescription
from pydantic import BaseModel

router = APIRouter(prefix="/api", tags=["camera"])

# ─── WebSocket stream endpoint ────────────────────────────────────────────────

@router.websocket("/ws/camera")
async def ws_camera(
    websocket: WebSocket,
    camera_url: Optional[str] = None,
    camera_id: Optional[int] = None,
    mode: str = 'ai'
):
    """
    WebSocket endpoint for live camera streaming.
    Pass either:
      ?camera_id=<id>           — use a saved camera (URL + name resolved from DB)
      ?camera_url=<rtsp://...>  — custom URL (no location tracking)
      &mode=ai|manage           — controls whether AI boxes are drawn
    """
    await websocket.accept()

    # Resolve camera URL + metadata from DB
    db = SessionLocal()
    try:
        staff_list = load_staff_list(db)
        cam_id_resolved: Optional[int] = None
        cam_name_resolved: Optional[str] = None

        if camera_id:
            cam = db.query(models.Camera).filter(models.Camera.id == camera_id).first()
            if cam:
                camera_url = cam.rtsp_url
                cam_id_resolved = cam.id
                cam_name_resolved = f"{cam.name}" + (f" — {cam.location}" if cam.location else "")
        # If camera_url still None → reject
        if not camera_url:
            await websocket.close(code=4000)
            return
    finally:
        db.close()

    # Start camera worker for this specific mode
    loop = asyncio.get_event_loop()
    worker_key = f"{cam_id_resolved}_{mode}"
    
    if worker_key not in active_workers:
        active_workers[worker_key] = CameraWorker()
        
    worker = active_workers[worker_key]
    if not worker.is_active():
        worker.start(
            camera_url, staff_list, loop,
            camera_id=cam_id_resolved,
            camera_name=cam_name_resolved,
        )

    # Per-client frame queue (maxsize=2 drops stale frames → keeps stream live)
    queue: asyncio.Queue = asyncio.Queue(maxsize=2)
    worker.add_client(queue, mode)

    # Pre-compute a loading frame
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
        pass
    except asyncio.TimeoutError:
        pass
    except asyncio.CancelledError:
        raise
    except Exception as e:
        print(f"[WS] Error: {e}")
    finally:
        worker.remove_client(queue)
        print("[WS] Client disconnected.")
        # If no clients left for this worker, stop the thread
        if not worker._client_queues:
            worker.stop()
            active_workers.pop(worker_key, None)


@router.websocket("/cameras/ws/status")
async def ws_cameras_status(websocket: WebSocket, db: Session = Depends(get_db)):
    """WebSocket endpoint to push camera online/offline status periodically."""
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


# ─── REST helper endpoints (kept for compatibility) ───────────────────────────

@router.get("/camera/start")
def start_camera(camera_url: str, db: Session = Depends(get_db)):
    # Deprecated / unused standalone start. 
    return {"status": "deprecated"}


@router.get("/camera/stop")
def stop_camera():
    for w in active_workers.values():
        w.stop()
    active_workers.clear()
    return {"status": "stopped"}


@router.get("/frame")
def get_frame():
    """Single frame endpoint (fallback for non-WS clients)."""
    # Requires selecting a specific worker, but for legacy compatibility we can pick the first one
    if not active_workers:
        frame = None
    else:
        worker = list(active_workers.values())[0]
        frame = worker.get_frame()
        
    if frame is None:
        placeholder = np.zeros((480, 640, 3), dtype=np.uint8)
        cv2.putText(placeholder, "No stream active", (160, 240),
                    cv2.FONT_HERSHEY_SIMPLEX, 1.0, (180, 180, 180), 2)
        _, buf = cv2.imencode(".jpg", placeholder)
        frame = buf.tobytes()

    return Response(
        content=frame,
        media_type="image/jpeg",
        headers={"Cache-Control": "no-store"},
    )


@router.get("/cameras/{camera_id}/status")
def get_camera_status(camera_id: int, db: Session = Depends(get_db)):
    cam = db.query(models.Camera).filter(models.Camera.id == camera_id).first()
    if not cam:
        raise HTTPException(status_code=404, detail="Camera not found")

    try:
        # Fast TCP check on the RTSP host and port
        parsed = urlparse(cam.rtsp_url)
        host = parsed.hostname
        port = parsed.port or 554
        if not host:
            return {"status": "offline"}

        with socket.create_connection((host, port), timeout=2.0):
            return {"status": "online"}
    except Exception:
        return {"status": "offline"}


@router.get("/cameras/{camera_id}/snapshot")
def get_camera_snapshot(camera_id: int, db: Session = Depends(get_db)):
    cam = db.query(models.Camera).filter(models.Camera.id == camera_id).first()
    if not cam:
        raise HTTPException(status_code=404, detail="Camera not found")

    try:
        # Use OpenCV to grab a single frame
        # Set options to prefer TCP and a 5-second timeout to match the old behavior
        os.environ["OPENCV_FFMPEG_CAPTURE_OPTIONS"] = "rtsp_transport;tcp|stimeout;5000000"

        cap = cv2.VideoCapture(cam.rtsp_url, cv2.CAP_FFMPEG)
        if not cap.isOpened():
            raise HTTPException(status_code=504, detail="Camera snapshot timed out or connection failed")

        ret, frame = cap.read()
        cap.release()

        if ret and frame is not None:
            success, encoded_image = cv2.imencode('.jpg', frame)
            if success:
                return Response(content=encoded_image.tobytes(), media_type="image/jpeg")
            raise HTTPException(status_code=503, detail="Failed to encode frame")
        else:
            raise HTTPException(status_code=503, detail="Failed to grab frame using OpenCV")

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

class WebRTCOffer(BaseModel):
    sdp: str
    type: str

peer_connections = set()

@router.post("/webrtc/offer")
async def webrtc_offer(
    offer: WebRTCOffer,
    camera_url: Optional[str] = None,
    camera_id: Optional[int] = None,
    mode: str = 'webrtc_ai'
):
    db = SessionLocal()
    try:
        staff_list = load_staff_list(db)
        cam_id_resolved: Optional[int] = None
        cam_name_resolved: Optional[str] = None

        if camera_id:
            cam = db.query(models.Camera).filter(models.Camera.id == camera_id).first()
            if cam:
                camera_url = cam.rtsp_url
                cam_id_resolved = cam.id
                cam_name_resolved = f"{cam.name}" + (f" — {cam.location}" if cam.location else "")
        if not camera_url:
            raise HTTPException(status_code=400, detail="Missing camera_url or invalid camera_id")
    finally:
        db.close()

    loop = asyncio.get_event_loop()
    # Ensure worker mode maps correctly (webrtc_ai or webrtc_manage)
    worker_key = f"{cam_id_resolved}_{mode.replace('webrtc_', '')}"
    
    if worker_key not in active_workers:
        active_workers[worker_key] = CameraWorker()
        
    worker = active_workers[worker_key]
    if not worker.is_active():
        worker.start(
            camera_url, staff_list, loop,
            camera_id=cam_id_resolved,
            camera_name=cam_name_resolved,
        )

    queue = asyncio.Queue(maxsize=2)
    worker.add_client(queue, mode)

    pc = RTCPeerConnection()
    peer_connections.add(pc)

    @pc.on("connectionstatechange")
    async def on_connectionstatechange():
        if pc.connectionState == "failed" or pc.connectionState == "closed":
            worker.remove_client(queue)
            peer_connections.discard(pc)

    video_track = CameraVideoStreamTrack(queue)
    pc.addTrack(video_track)

    offer_obj = RTCSessionDescription(sdp=offer.sdp, type=offer.type)
    await pc.setRemoteDescription(offer_obj)

    answer = await pc.createAnswer()
    await pc.setLocalDescription(answer)

    return {"sdp": pc.localDescription.sdp, "type": pc.localDescription.type}
