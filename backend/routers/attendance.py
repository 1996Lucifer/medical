import datetime
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel, ConfigDict

from database import get_db
import models

router = APIRouter(prefix="/api/attendance", tags=["attendance"])

class AttendanceResponse(BaseModel):
    id: int
    staff_id: Optional[int]
    staff_name: str
    confidence: float
    date: datetime.date
    entry_time: datetime.datetime
    last_seen: Optional[datetime.datetime]
    exit_time: Optional[datetime.datetime]
    camera_id: Optional[int]
    camera_name: Optional[str]
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
    record.exit_time = datetime.datetime.now(tz=datetime.timezone.utc)
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
    return {"status": "deleted"}
