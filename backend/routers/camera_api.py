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
    db.delete(cam)
    db.commit()
    return {"status": "deleted"}
