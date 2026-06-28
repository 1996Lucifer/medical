from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
import datetime

from database import get_db
import models

router = APIRouter(prefix="/api/analytics", tags=["analytics"])

@router.get("/attendance-summary")
def get_attendance_summary(days: int = 7, db: Session = Depends(get_db)):
    """
    Returns a daily summary of attendance for the last `days` days.
    """
    start_date = datetime.date.today() - datetime.timedelta(days=days)
    
    records = db.query(models.Attendance).filter(
        models.Attendance.date >= start_date
    ).all()
    
    summary = {}
    
    for record in records:
        date_str = record.date.isoformat()
        if date_str not in summary:
            summary[date_str] = []
            
        exit_time = record.exit_time or record.last_seen
        if exit_time and record.entry_time:
            duration = (exit_time - record.entry_time).total_seconds() / 3600.0
        else:
            duration = 0.0
            
        summary[date_str].append({
            "staff_name": record.staff_name,
            "entry_time": record.entry_time.isoformat() if record.entry_time else None,
            "exit_time": exit_time.isoformat() if exit_time else None,
            "duration_hours": round(duration, 2),
            "camera_name": record.camera_name,
        })
        
    return summary
