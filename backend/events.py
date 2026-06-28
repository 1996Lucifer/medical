import datetime
import json
from typing import Optional
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
        details: Optional[dict] = None,
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
                details=json.dumps(details) if details else None,
            )

            db.add(event)
            db.commit()

            print(
                f"[EventEngine] 🔔 {event_type} event recorded at {camera_name or 'Unknown Location'}"
            )

            # Evaluate rules asynchronously (or synchronously for now)
            from rules import security_rules_engine

            security_rules_engine.evaluate_event(
                event_type=event_type,
                camera_id=camera_id,
                camera_name=camera_name,
                confidence=confidence,
                details=details or {},
            )

        except Exception as e:
            print(f"[EventEngine] Failed to publish event: {e}")
            db.rollback()
        finally:
            db.close()


# Global instance
event_engine = EventEngine()
