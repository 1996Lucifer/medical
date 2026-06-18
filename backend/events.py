import datetime
import json
from typing import Optional
from sqlalchemy.orm import Session
from database import SessionLocal
import models

class EventEngine:
    def __init__(self):
        pass

    def publish_event(
        self,
        event_type: str,
        camera_id: Optional[int] = None,
        camera_name: Optional[str] = None,
        confidence: Optional[float] = None,
        snapshot_path: Optional[str] = None,
        details: Optional[dict] = None
    ):
        """
        Publish an event to the system.
        """
        db = SessionLocal()
        try:
            now = datetime.datetime.now(tz=datetime.timezone.utc)
            
            event = models.SystemEvent(
                event_type=event_type,
                camera_id=camera_id,
                camera_name=camera_name,
                confidence=confidence,
                snapshot_path=snapshot_path,
                timestamp=now,
                details=json.dumps(details) if details else None
            )
            
            db.add(event)
            db.commit()
            
            print(f"[EventEngine] 🔔 {event_type} event recorded at {camera_name or 'Unknown Location'}")
            
        except Exception as e:
            print(f"[EventEngine] Error publishing event: {e}")
            db.rollback()
        finally:
            db.close()

# Singleton instance
event_engine = EventEngine()
