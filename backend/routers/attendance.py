import datetime
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel, ConfigDict

from database import get_db
import models
from camera.attendance_service import checkout_session
from indoor_tracking.hub import hub
from routers.auth import get_current_user

router = APIRouter(prefix="/api/attendance", tags=["attendance"])

class AttendanceResponse(BaseModel):
    id: int
    staff_id: Optional[int]
    staff_name: str
    role: str
    confidence: Optional[float]
    date: datetime.date
    entry_time: datetime.datetime
    last_seen: Optional[datetime.datetime]
    exit_time: Optional[datetime.datetime]
    camera_id: Optional[int]
    camera_name: Optional[str]
    # "face" (default, camera recognition), "rfid" (badge tap), or "manual".
    source: str = "face"
    model_config = ConfigDict(from_attributes=True)


@router.get("", response_model=List[AttendanceResponse])
def get_attendance(
    date: Optional[str] = None,
    db: Session = Depends(get_db)
):
    """
    Get attendance sessions for a specific date (defaults to today).
    Each record is one shift session per staff member.
    """
    filter_date = (
        datetime.date.fromisoformat(date) if date else datetime.date.today()
    )
    records = (
        db.query(models.Attendance)
        .filter(models.Attendance.date == filter_date)
        .order_by(models.Attendance.entry_time.desc())
        .all()
    )
    return records


@router.get("/me", response_model=Optional[AttendanceResponse])
def get_my_open_session(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """
    The current user's own open attendance session, if any - used by the
    mobile app to know when to start sending indoor-tracking signals (a
    check-in happens via the face/RFID pipeline, not an app action, so the
    app has to poll for "am I checked in right now").
    """
    staff = db.query(models.Staff).filter(models.Staff.user_id == current_user.id).first()
    if staff is None:
        return None
    return (
        db.query(models.Attendance)
        .filter(models.Attendance.staff_id == staff.id, models.Attendance.exit_time.is_(None))
        .order_by(models.Attendance.entry_time.desc())
        .first()
    )


@router.post("/{attendance_id}/checkout")
def checkout_attendance(attendance_id: int, db: Session = Depends(get_db)):
    """
    Manually set exit_time for an attendance session.
    Call this when the person leaves or at end of shift.
    """
    record = db.query(models.Attendance).filter(
        models.Attendance.id == attendance_id
    ).first()
    if not record:
        raise HTTPException(status_code=404, detail="Record not found")
    if record.exit_time:
        raise HTTPException(status_code=400, detail="Already checked out")
    checkout_session(db, record, datetime.datetime.now(tz=datetime.timezone.utc), reason="manual")
    db.commit()
    return {"status": "checked_out", "exit_time": record.exit_time.isoformat()}


@router.delete("/{attendance_id}")
def delete_attendance(attendance_id: int, db: Session = Depends(get_db)):
    record = db.query(models.Attendance).filter(
        models.Attendance.id == attendance_id
    ).first()
    if not record:
        raise HTTPException(status_code=404, detail="Record not found")
    db.delete(record)
    db.commit()
    hub.stop_session(attendance_id)
    return {"status": "deleted"}
