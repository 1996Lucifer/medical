import os
import shutil
import datetime
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from sqlalchemy.orm import Session
from pydantic import BaseModel, ConfigDict

from database import get_db
import models
from camera.vision_service import vision_service

router = APIRouter(prefix="/api/staff", tags=["staff"])

class StaffResponse(BaseModel):
    id: int
    name: str
    photo_count: int = 0
    model_config = ConfigDict(from_attributes=True)


class StaffPhotoResponse(BaseModel):
    id: int
    staff_id: int
    label: Optional[str]
    created_at: datetime.datetime
    model_config = ConfigDict(from_attributes=True)


class StaffUpdate(BaseModel):
    name: str


def load_staff_list(db: Session) -> list:
    """
    Load ALL embeddings for all staff members — both the primary photo
    and every additional photo — as a flat list of {name, embedding}.
    """
    staff_records = db.query(models.Staff).all()
    staff_list = []
    for s in staff_records:
        if s.embedding is not None:
            staff_list.append({"name": s.name, "embedding": s.embedding})
        for photo in s.photos:
            staff_list.append({"name": s.name, "embedding": photo.embedding})
    return staff_list


@router.post("", response_model=StaffResponse)
async def register_staff(
    name: str, file: UploadFile = File(...), db: Session = Depends(get_db)
):
    """Register a new staff member with their first face photo."""
    temp_file_path = f"temp_staff_{file.filename}"
    try:
        with open(temp_file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        embedding = vision_service.extract_embedding(temp_file_path)
        if embedding is None:
            raise HTTPException(status_code=400, detail="No face detected in the image.")

        db_staff = models.Staff(name=name, embedding=embedding.tolist())
        db.add(db_staff)
        db.commit()
        db.refresh(db_staff)

        return StaffResponse(id=db_staff.id, name=db_staff.name, photo_count=1)
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if os.path.exists(temp_file_path):
            os.remove(temp_file_path)


@router.post("/{staff_id}/photo", response_model=StaffPhotoResponse)
async def add_staff_photo(
    staff_id: int,
    file: UploadFile = File(...),
    label: Optional[str] = None,
    db: Session = Depends(get_db),
):
    """Add an additional face photo for an existing staff member."""
    staff = db.query(models.Staff).filter(models.Staff.id == staff_id).first()
    if not staff:
        raise HTTPException(status_code=404, detail="Staff member not found.")

    temp_file_path = f"temp_extra_{staff_id}_{file.filename}"
    try:
        with open(temp_file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        embedding = vision_service.extract_embedding(temp_file_path)
        if embedding is None:
            raise HTTPException(status_code=400, detail="No face detected in the image.")

        photo = models.StaffPhoto(
            staff_id=staff_id,
            embedding=embedding.tolist(),
            label=label,
        )
        db.add(photo)
        db.commit()
        db.refresh(photo)
        return photo
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if os.path.exists(temp_file_path):
            os.remove(temp_file_path)


@router.get("/{staff_id}/photos", response_model=List[StaffPhotoResponse])
def get_staff_photos(staff_id: int, db: Session = Depends(get_db)):
    """List all extra photos registered for a staff member."""
    return db.query(models.StaffPhoto).filter(models.StaffPhoto.staff_id == staff_id).all()


@router.delete("/{staff_id}/photo/{photo_id}")
def delete_staff_photo(staff_id: int, photo_id: int, db: Session = Depends(get_db)):
    """Remove a specific extra photo from a staff member."""
    photo = db.query(models.StaffPhoto).filter(
        models.StaffPhoto.id == photo_id,
        models.StaffPhoto.staff_id == staff_id,
    ).first()
    if not photo:
        raise HTTPException(status_code=404, detail="Photo not found.")
    db.delete(photo)
    db.commit()
    return {"status": "deleted"}


@router.put("/{staff_id}", response_model=StaffResponse)
def update_staff(staff_id: int, body: StaffUpdate, db: Session = Depends(get_db)):
    """Update staff name."""
    staff = db.query(models.Staff).filter(models.Staff.id == staff_id).first()
    if not staff:
        raise HTTPException(status_code=404, detail="Staff not found.")
    staff.name = body.name
    db.commit()
    db.refresh(staff)
    return StaffResponse(id=staff.id, name=staff.name, photo_count=len(staff.photos) + (1 if staff.embedding is not None else 0))


@router.delete("/{staff_id}")
def delete_staff(staff_id: int, db: Session = Depends(get_db)):
    """Remove a staff member and all their photos."""
    staff = db.query(models.Staff).filter(models.Staff.id == staff_id).first()
    if not staff:
        raise HTTPException(status_code=404, detail="Staff not found.")
    db.delete(staff)
    db.commit()
    return {"status": "deleted"}


@router.get("", response_model=List[StaffResponse])
def get_staff(db: Session = Depends(get_db)):
    staff_records = db.query(models.Staff).all()
    result = []
    for s in staff_records:
        count = 1 if s.embedding is not None else 0
        count += len(s.photos)
        result.append(StaffResponse(id=s.id, name=s.name, photo_count=count))
    return result
