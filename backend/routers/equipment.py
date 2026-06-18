from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel, ConfigDict
import datetime

from database import get_db
import models

router = APIRouter(prefix="/api/equipment", tags=["equipment"])

class EquipmentTypeResponse(BaseModel):
    id: int
    name: str
    model_config = ConfigDict(from_attributes=True)

class EquipmentItemResponse(BaseModel):
    id: int
    equipment_id: str
    type_id: int
    current_location: Optional[str]
    last_seen: Optional[datetime.datetime]
    model_config = ConfigDict(from_attributes=True)

class EquipmentTrackingResponse(BaseModel):
    id: int
    equipment_item_id: int
    camera_id: Optional[int]
    camera_name: Optional[str]
    timestamp: datetime.datetime
    model_config = ConfigDict(from_attributes=True)


@router.get("/types", response_model=List[EquipmentTypeResponse])
def get_equipment_types(db: Session = Depends(get_db)):
    """List all equipment types."""
    return db.query(models.EquipmentType).all()

@router.get("", response_model=List[EquipmentItemResponse])
def list_equipment(db: Session = Depends(get_db)):
    """List all tracked equipment instances."""
    return db.query(models.EquipmentItem).all()

@router.get("/{equipment_id}/tracking", response_model=List[EquipmentTrackingResponse])
def get_equipment_tracking(equipment_id: int, db: Session = Depends(get_db)):
    """Get the movement timeline for a specific piece of equipment."""
    item = db.query(models.EquipmentItem).filter(models.EquipmentItem.id == equipment_id).first()
    if not item:
        raise HTTPException(status_code=404, detail="Equipment not found")
        
    return db.query(models.EquipmentTracking)\
        .filter(models.EquipmentTracking.equipment_item_id == equipment_id)\
        .order_by(models.EquipmentTracking.timestamp.desc())\
        .all()
