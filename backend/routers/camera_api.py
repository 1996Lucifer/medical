from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel, ConfigDict

from database import get_db
import models

router = APIRouter(prefix="/api/cameras", tags=["cameras"])

class CameraCreate(BaseModel):
    name: str
    location: Optional[str] = None
    rtsp_url: str

class CameraResponse(BaseModel):
    id: int
    name: str
    location: Optional[str]
    rtsp_url: str
    model_config = ConfigDict(from_attributes=True)


@router.post("", response_model=CameraResponse)
def create_camera(body: CameraCreate, db: Session = Depends(get_db)):
    """Register a new camera with its RTSP URL and location."""
    cam = models.Camera(name=body.name, location=body.location, rtsp_url=body.rtsp_url)
    db.add(cam)
    db.commit()
    db.refresh(cam)
    return cam


@router.get("", response_model=List[CameraResponse])
def list_cameras(db: Session = Depends(get_db)):
    return db.query(models.Camera).all()


@router.put("/{camera_id}", response_model=CameraResponse)
def update_camera(camera_id: int, body: CameraCreate, db: Session = Depends(get_db)):
    cam = db.query(models.Camera).filter(models.Camera.id == camera_id).first()
    if not cam:
        raise HTTPException(status_code=404, detail="Camera not found")
    cam.name = body.name
    cam.location = body.location
    cam.rtsp_url = body.rtsp_url
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
