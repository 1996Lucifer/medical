import asyncio
import urllib.parse
from typing import List, Optional, Dict
from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session
from pydantic import BaseModel, ConfigDict

from database import get_db
import models

router = APIRouter(prefix="/api/cameras", tags=["cameras"])

class CameraCreate(BaseModel):
    name: str
    location: Optional[str] = None
    rtsp_url: str
    ha_entity_id: Optional[str] = None

class CameraResponse(BaseModel):
    id: int
    name: str
    location: Optional[str]
    rtsp_url: str
    ha_entity_id: Optional[str]
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
def create_camera(body: CameraCreate, db: Session = Depends(get_db)):
    """Register a new camera with its RTSP URL and location."""
    cam = models.Camera(name=body.name, location=body.location, rtsp_url=body.rtsp_url, ha_entity_id=body.ha_entity_id)
    db.add(cam)
    db.commit()
    db.refresh(cam)
    return cam


@router.get("", response_model=List[CameraResponse])
def list_cameras(db: Session = Depends(get_db)):
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
async def get_cameras_status(db: Session = Depends(get_db)):
    """Ping all camera RTSP streams to check if they are online."""
    cameras = db.query(models.Camera).all()
    tasks = [_check_rtsp(c.id, c.rtsp_url) for c in cameras]
    results = await asyncio.gather(*tasks)
    return {cam_id: status for cam_id, status in results}




@router.put("/{camera_id}", response_model=CameraResponse)
def update_camera(camera_id: int, body: CameraCreate, db: Session = Depends(get_db)):
    cam = db.query(models.Camera).filter(models.Camera.id == camera_id).first()
    if not cam:
        raise HTTPException(status_code=404, detail="Camera not found")
    cam.name = body.name
    cam.location = body.location
    cam.rtsp_url = body.rtsp_url
    cam.ha_entity_id = body.ha_entity_id
    db.commit()
    db.refresh(cam)
    return cam


@router.delete("/{camera_id}")
def delete_camera(camera_id: int, db: Session = Depends(get_db)):
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
def get_camera_rois(camera_id: int, db: Session = Depends(get_db)):
    rois = db.query(models.CameraROI).filter(models.CameraROI.camera_id == camera_id).all()
    return rois

@router.post("/{camera_id}/rois", response_model=ROIResponse)
def create_camera_roi(camera_id: int, body: ROICreate, db: Session = Depends(get_db)):
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
def delete_camera_roi(roi_id: int, db: Session = Depends(get_db)):
    roi = db.query(models.CameraROI).filter(models.CameraROI.id == roi_id).first()
    if not roi:
        raise HTTPException(status_code=404, detail="ROI not found")
        
    db.delete(roi)
    db.commit()
    return {"status": "deleted"}

@router.get("/rois/all/unique", response_model=List[str])
def get_all_unique_rois(db: Session = Depends(get_db)):
    zones = db.query(models.CameraROI.zone_name).distinct().all()
    return [z[0] for z in zones]
