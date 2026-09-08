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

@router.get("/{patient_id}", response_model=PatientResponse)
def get_patient(patient_id: int, db: Session = Depends(get_db)):
    from fastapi import HTTPException
    patient = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    return patient

class PatientUpdateRequest(BaseModel):
    name: str | None = None
    mrn: str | None = None
    dob: datetime.date | None = None
    gender: str | None = None

@router.put("/{patient_id}", response_model=PatientResponse)
def update_patient(patient_id: int, req: PatientUpdateRequest, db: Session = Depends(get_db)):
    from fastapi import HTTPException
    patient = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    
    if req.name is not None:
        patient.name = req.name
    if req.mrn is not None:
        patient.mrn = req.mrn
    if req.dob is not None:
        patient.dob = req.dob
    if req.gender is not None:
        patient.gender = req.gender
        
    db.commit()
    db.refresh(patient)
    return patient
