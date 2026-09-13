from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List, Optional
from pydantic import BaseModel, ConfigDict
import datetime

from database import get_db
import models
from routers.auth import get_current_user, require_permission
from services.auth_provisioning import create_login_account

router = APIRouter(prefix="/api/patients", tags=["patients"])


def _assert_patient_access(patient_id: int, current_user: models.User):
    """
    A patient (role == 'patient') may only ever access their own record -
    everyone else (staff/admin) can access any patient, matching existing
    behavior. Without this, any patient's JWT could read/write any other
    patient_id simply by changing the URL.
    """
    if current_user.role == "patient":
        own_patient = current_user.patient_profile
        if own_patient is None or own_patient.id != patient_id:
            raise HTTPException(status_code=403, detail="You do not have access to this patient record.")


class PatientResponse(BaseModel):
    id: int
    name: str
    mrn: str | None = None
    dob: datetime.date | None = None
    gender: str | None = None
    created_at: datetime.datetime | None = None
    has_portal_login: bool = False

    model_config = ConfigDict(from_attributes=True)

@router.get("", response_model=List[PatientResponse])
def get_patients(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """
    Fetch all registered patients - staff/admin only. A patient's own token
    must never see this (it's every patient's PHI, not just their own).
    """
    if current_user.role == "patient":
        raise HTTPException(status_code=403, detail="You do not have access to this resource.")
    patients = db.query(models.Patient).all()
    return [
        PatientResponse(
            id=p.id, name=p.name, mrn=p.mrn, dob=p.dob, gender=p.gender,
            created_at=p.created_at, has_portal_login=p.user_id is not None,
        )
        for p in patients
    ]

@router.get("/{patient_id}", response_model=PatientResponse)
def get_patient(
    patient_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    patient = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    _assert_patient_access(patient_id, current_user)
    return PatientResponse(
        id=patient.id, name=patient.name, mrn=patient.mrn, dob=patient.dob,
        gender=patient.gender, created_at=patient.created_at,
        has_portal_login=patient.user_id is not None,
    )

class PatientUpdateRequest(BaseModel):
    name: str | None = None
    mrn: str | None = None
    dob: datetime.date | None = None
    gender: str | None = None

@router.put("/{patient_id}", response_model=PatientResponse)
def update_patient(
    patient_id: int,
    req: PatientUpdateRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    patient = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    _assert_patient_access(patient_id, current_user)

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
    return PatientResponse(
        id=patient.id, name=patient.name, mrn=patient.mrn, dob=patient.dob,
        gender=patient.gender, created_at=patient.created_at,
        has_portal_login=patient.user_id is not None,
    )


class CreateLoginResponse(BaseModel):
    username: str
    temp_password: str


@router.post("/{patient_id}/create-login", response_model=CreateLoginResponse)
def create_patient_login(
    patient_id: int,
    db: Session = Depends(get_db),
    _admin: models.User = Depends(require_permission("manage_patients")),
):
    """
    Provisions portal login access for a patient (a User row with
    role="patient", linked via Patient.user_id) - reuses the same
    username/temp-password/change-password-on-first-login flow used for
    staff onboarding. Admin communicates the temp password to the patient
    out of band; it is never stored or shown again after this response.
    """
    patient = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    if patient.user_id is not None:
        raise HTTPException(status_code=400, detail="This patient already has portal login access.")

    new_user, temp_password = create_login_account(db, patient.name, "patient", fallback_username="patient")
    if new_user is None:
        raise HTTPException(status_code=500, detail="Failed to create login account.")

    patient.user_id = new_user.id
    db.commit()

    return CreateLoginResponse(username=new_user.username, temp_password=temp_password)


class DoctorContact(BaseModel):
    staff_id: int
    user_id: Optional[int] = None
    name: str
    role: Optional[str] = None
    can_call: bool


@router.get("/{patient_id}/doctors", response_model=List[DoctorContact])
def get_patient_doctors(
    patient_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """
    Doctors this patient has actually been seen by (derived from
    Consultation.staff_id) - the only doctors a patient is allowed to call
    (see services/calls/authorization.py). A doctor only shows as callable
    once they have their own login account (Staff.user_id).
    """
    patient = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    _assert_patient_access(patient_id, current_user)

    staff_rows = (
        db.query(models.Staff)
        .join(models.Consultation, models.Consultation.staff_id == models.Staff.id)
        .filter(models.Consultation.patient_id == patient_id)
        .distinct()
        .all()
    )
    return [
        DoctorContact(
            staff_id=s.id, user_id=s.user_id, name=s.name, role=s.role,
            can_call=s.user_id is not None,
        )
        for s in staff_rows
    ]
