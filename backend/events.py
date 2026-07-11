import datetime
import json
from typing import Optional
from typing import Dict, Any, Callable
import time
import threading

# ── Zone Alerts ─────────────────────────────────────────────────────────────
global_zone_alerts: Dict[str, float] = {}
zone_alerts_lock = threading.Lock()

def set_zone_alert(camera_name: str, duration_sec: float = 5.0):
    with zone_alerts_lock:
        global_zone_alerts[camera_name] = time.monotonic() + duration_sec

def is_zone_alerted(camera_name: str) -> bool:
    with zone_alerts_lock:
        exp = global_zone_alerts.get(camera_name, 0.0)
        return time.monotonic() < exp

from database import SessionLocal
import models


import asyncio

class EventEngine:
    def __init__(self):
        self.active_websockets = set()

    def connect(self, websocket):
        self.active_websockets.add(websocket)
        if getattr(self, '_loop', None) is None:
            self._loop = asyncio.get_running_loop()
        
    def disconnect(self, websocket):
        self.active_websockets.discard(websocket)

    def _broadcast(self, event_data: dict):
        if not self.active_websockets:
            return
            
        loop = getattr(self, '_loop', None)
        if not loop:
            return
            
        for ws in list(self.active_websockets):
            try:
                asyncio.run_coroutine_threadsafe(ws.send_json(event_data), loop)
            except Exception:
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
            
            # Broadcast to WebSocket clients
            event_payload = {
                "id": event.id,
                "event_type": event_type,
                "camera_id": camera_id,
                "camera_name": camera_name,
                "confidence": confidence,
                "snapshot_path": snapshot_path,
                "timestamp": now.isoformat(),
                "details": details
            }
            self._broadcast(event_payload)

        except Exception as e:
            print(f"[EventEngine] Failed to publish event: {e}")
            db.rollback()
        finally:
            db.close()


# Global instance
event_engine = EventEngine()
