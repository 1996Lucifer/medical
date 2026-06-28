from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from typing import List
from pydantic import BaseModel, ConfigDict
import datetime

from database import get_db
import models

router = APIRouter(prefix="/api/patients", tags=["patients"])

class PatientResponse(BaseModel):
    id: int
    name: str
    mrn: str | None = None
    dob: datetime.date | None = None
    gender: str | None = None
    created_at: datetime.datetime | None = None
    
    model_config = ConfigDict(from_attributes=True)

@router.get("", response_model=List[PatientResponse])
def get_patients(db: Session = Depends(get_db)):
    """
    Fetch all registered patients.
    """
    return db.query(models.Patient).all()
