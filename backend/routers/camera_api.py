import asyncio
import urllib.parse
from typing import List, Optional, Dict
from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session
from pydantic import BaseModel, ConfigDict

from database import get_db
import models
from routers.auth import get_current_user, require_permission

router = APIRouter(prefix="/api/cameras", tags=["cameras"])


@router.post("/warmup")
async def warmup_cameras(
    _user: models.User = Depends(require_permission("view_camera")),
):
    """
    Kick off the AI vision models' cold-start load (InsightFace + YOLO,
    ~30-60s) in the background, without connecting to any specific
    camera's stream. Meant to be called right after login by any role
    with view_camera - so that cost pays off before the user navigates
    into the camera screen, instead of blocking whatever camera they open
    first. Fire-and-forget: returns immediately, does not wait for the
    models to finish loading.
    """
    from camera.vision_worker import vision_process_manager

    vision_process_manager.warmup()
    return {"status": "warming_up"}

def parse_rtsp_url(url: str) -> dict:
    if not url:
        return {"ip_address": "127.0.0.1", "port": 554, "username": None, "password": None, "stream_path": ""}
    raw_url = url if url.startswith("rtsp://") else f"rtsp://{url}"
    parsed = urllib.parse.urlparse(raw_url)
    return {
        "ip_address": parsed.hostname or "127.0.0.1",
        "port": parsed.port or 554,
        "username": parsed.username or None,
        "password": parsed.password or None,
        "stream_path": parsed.path or "",
    }

class CameraCreate(BaseModel):
    name: str
    location: Optional[str] = None
    ip_address: Optional[str] = "127.0.0.1"
    port: Optional[int] = 554
    username: Optional[str] = None
    password: Optional[str] = None
    stream_path: Optional[str] = None
    rtsp_url: Optional[str] = None

class CameraResponse(BaseModel):
    id: int
    name: str
    location: Optional[str] = None
    ip_address: Optional[str] = "127.0.0.1"
    port: Optional[int] = 554
    username: Optional[str] = None
    password: Optional[str] = None
    stream_path: Optional[str] = None
    rtsp_url: str
    is_restricted: Optional[bool] = False
    model_config = ConfigDict(from_attributes=True)

class ROICreate(BaseModel):
    zone_name: str
    points: str

class ROIResponse(BaseModel):
    id: int
    camera_id: int
    zone_name: str
    points: str
    model_config = ConfigDict(from_attributes=True)


@router.post("", response_model=CameraResponse)
def create_camera(body: CameraCreate, db: Session = Depends(get_db), _user: models.User = Depends(get_current_user)):
    """Register a new camera with structured connection details."""
    ip = body.ip_address
    port = body.port or 554
    user = body.username
    pwd = body.password
    path = body.stream_path

    if body.rtsp_url and (not ip or (ip == "127.0.0.1" and not user and not path)):
        parsed = parse_rtsp_url(body.rtsp_url)
        ip = parsed["ip_address"]
        port = parsed["port"]
        user = parsed["username"] or user
        pwd = parsed["password"] or pwd
        path = parsed["stream_path"] or path

    cam = models.Camera(
        name=body.name,
        location=body.location,
        ip_address=ip or "127.0.0.1",
        port=port,
        username=user,
        password=pwd,
        stream_path=path,
    )
    db.add(cam)
    db.commit()
    db.refresh(cam)
    return cam


@router.get("", response_model=List[CameraResponse])
def list_cameras(db: Session = Depends(get_db), _user: models.User = Depends(get_current_user)):
    return db.query(models.Camera).all()


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

@router.get("/status", response_model=Dict[int, bool])
async def get_cameras_status(db: Session = Depends(get_db), _user: models.User = Depends(get_current_user)):
    """Ping all camera RTSP streams to check if they are online."""
    cameras = db.query(models.Camera).all()
    tasks = [_check_rtsp(c.id, c.rtsp_url) for c in cameras]
    results = await asyncio.gather(*tasks)
    return {cam_id: status for cam_id, status in results}


@router.get("/{camera_id}", response_model=CameraResponse)
def get_camera(camera_id: int, db: Session = Depends(get_db), _user: models.User = Depends(get_current_user)):
    """
    Fetch a single camera by id — needed so the settings-detail page can be
    reached directly by URL (/settings/cameras/:id) and load its own data
    instead of requiring the full camera object to be passed in-memory
    from the list screen.
    """
    cam = db.query(models.Camera).filter(models.Camera.id == camera_id).first()
    if not cam:
        raise HTTPException(status_code=404, detail="Camera not found.")
    return cam




@router.put("/{camera_id}", response_model=CameraResponse)
def update_camera(camera_id: int, body: CameraCreate, db: Session = Depends(get_db), _user: models.User = Depends(get_current_user)):
    cam = db.query(models.Camera).filter(models.Camera.id == camera_id).first()
    if not cam:
        raise HTTPException(status_code=404, detail="Camera not found")

    ip = body.ip_address
    port = body.port or 554
    user = body.username
    pwd = body.password
    path = body.stream_path

    if body.rtsp_url and (not ip or (ip == "127.0.0.1" and not user and not path)):
        parsed = parse_rtsp_url(body.rtsp_url)
        ip = parsed["ip_address"]
        port = parsed["port"]
        user = parsed["username"] or user
        pwd = parsed["password"] or pwd
        path = parsed["stream_path"] or path

    cam.name = body.name
    cam.location = body.location
    cam.ip_address = ip or "127.0.0.1"
    cam.port = port
    cam.username = user
    cam.password = pwd
    cam.stream_path = path

    db.commit()
    db.refresh(cam)
    return cam


@router.delete("/{camera_id}")
def delete_camera(camera_id: int, db: Session = Depends(get_db), _user: models.User = Depends(get_current_user)):
    cam = db.query(models.Camera).filter(models.Camera.id == camera_id).first()
    if not cam:
        raise HTTPException(status_code=404, detail="Camera not found")
    
    # Check for linked records
    has_attendance = db.query(models.Attendance).filter(models.Attendance.camera_id == camera_id).first() is not None
    has_events = db.query(models.SystemEvent).filter(models.SystemEvent.camera_id == camera_id).first() is not None
    has_alerts = db.query(models.SecurityAlert).filter(models.SecurityAlert.camera_id == camera_id).first() is not None
    
    if has_attendance or has_events or has_alerts:
        raise HTTPException(
            status_code=400, 
            detail="Cannot delete camera because it is linked to existing attendance, event, or security alert records. Please unlink or reassign them first."
        )
    
    db.delete(cam)
    db.commit()
    return {"status": "deleted"}


@router.get("/{camera_id}/rois", response_model=List[ROIResponse])
def get_camera_rois(camera_id: int, db: Session = Depends(get_db), _user: models.User = Depends(get_current_user)):
    rois = db.query(models.CameraROI).filter(models.CameraROI.camera_id == camera_id).all()
    return rois

@router.post("/{camera_id}/rois", response_model=ROIResponse)
def create_camera_roi(camera_id: int, body: ROICreate, db: Session = Depends(get_db), _user: models.User = Depends(get_current_user)):
    cam = db.query(models.Camera).filter(models.Camera.id == camera_id).first()
    if not cam:
        raise HTTPException(status_code=404, detail="Camera not found")
        
    roi = models.CameraROI(
        camera_id=camera_id,
        zone_name=body.zone_name,
        points=body.points
    )
    db.add(roi)
    db.commit()
    db.refresh(roi)
    return roi

@router.delete("/rois/{roi_id}")
def delete_camera_roi(roi_id: int, db: Session = Depends(get_db), _user: models.User = Depends(get_current_user)):
    roi = db.query(models.CameraROI).filter(models.CameraROI.id == roi_id).first()
    if not roi:
        raise HTTPException(status_code=404, detail="ROI not found")
        
    db.delete(roi)
    db.commit()
    return {"status": "deleted"}

@router.get("/rois/all/unique", response_model=List[str])
def get_all_unique_rois(db: Session = Depends(get_db), _user: models.User = Depends(get_current_user)):
    zones = db.query(models.CameraROI.zone_name).distinct().all()
    return [z[0] for z in zones]
