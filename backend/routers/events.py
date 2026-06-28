from typing import List, Optional
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from pydantic import BaseModel, ConfigDict
import datetime

from database import get_db
import models

router = APIRouter(prefix="/api/events", tags=["events"])

class SystemEventResponse(BaseModel):
    id: int
    event_type: str
    camera_id: Optional[int]
    camera_name: Optional[str]
    confidence: Optional[float]
    snapshot_path: Optional[str]
    timestamp: datetime.datetime
    details: Optional[str]
    model_config = ConfigDict(from_attributes=True)


@router.get("", response_model=List[SystemEventResponse])
def get_events(
    event_type: Optional[str] = None,
    limit: int = 100,
    db: Session = Depends(get_db)
):
    """List recent system events (e.g. Attendance, EquipmentDetection, TheftDetection)."""
    query = db.query(models.SystemEvent)
    if event_type:
        query = query.filter(models.SystemEvent.event_type == event_type)
        
    return query.order_by(models.SystemEvent.timestamp.desc()).limit(limit).all()


@router.get("/timeline")
def get_timeline(
    date_str: Optional[str] = None,
    staff_name: Optional[str] = None,
    db: Session = Depends(get_db)
):
    """Returns a correlated chronological timeline of events for a specific day."""
    from correlation_engine import correlation_engine
    
    if date_str:
        try:
            target_date = datetime.datetime.strptime(date_str, "%Y-%m-%d").date()
        except ValueError:
            target_date = datetime.date.today()
    else:
        target_date = datetime.date.today()
        
    timeline = correlation_engine.get_timeline(db, date=target_date, staff_name=staff_name)
    return {"date": target_date.isoformat(), "timeline": timeline}
