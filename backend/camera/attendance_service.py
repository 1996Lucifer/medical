import datetime
import threading
from typing import Optional

from database import SessionLocal
import models
from events import event_engine

# ── Attendance session constants ──────────────────────────────────────────────
SESSION_GAP_SEC    = 5 * 3600   # 5 hours of absence → new session / new entry
LAST_SEEN_FREQ_SEC = 30         # update last_seen at most every 30 seconds

# Per-person in-memory timestamps (avoids hitting DB on every frame)
_last_db_write: dict   = {}   # {name: datetime} — when we last wrote to DB
_last_db_write_lock = threading.Lock()

def _maybe_mark_attendance(
    name: str, score: float,
    camera_id: Optional[int] = None,
    camera_name: Optional[str] = None,
    **kwargs
):
    """
    Session-aware attendance marking:

    1. If last DB write for this person was < LAST_SEEN_FREQ_SEC ago → skip (throttle).
    2. Look up the most recent Attendance record for this person (any date).
    3. If NO record exists OR last_seen > SESSION_GAP_SEC ago
           → create a NEW session record (entry_time = now).
    4. Otherwise
           → update last_seen on the existing open session.
       (exit_time is set manually via the checkout API, never here.)
    """
    if name == "Unknown":
        now = datetime.datetime.now(tz=datetime.timezone.utc)
        throttle_key = f"unknown_{camera_id}"
        with _last_db_write_lock:
            last_write = _last_db_write.get(throttle_key)
            if last_write and (now - last_write).total_seconds() < LAST_SEEN_FREQ_SEC:
                return False
            _last_db_write[throttle_key] = now

        event_engine.publish_event(
            event_type="UnknownFaceDetected",
            camera_id=camera_id,
            camera_name=camera_name,
            confidence=score,
            details={"status": "detected"}
        )
        return True

    now = datetime.datetime.now(tz=datetime.timezone.utc)

    # In-memory throttle — skip DB entirely if we wrote recently
    with _last_db_write_lock:
        last_write = _last_db_write.get(name)
        if last_write and (now - last_write).total_seconds() < LAST_SEEN_FREQ_SEC:
            return False
        _last_db_write[name] = now

    db = SessionLocal()
    try:
        # Find most recent attendance record for this person
        latest: Optional[models.Attendance] = (
            db.query(models.Attendance)
            .filter(models.Attendance.staff_name == name)
            .order_by(models.Attendance.last_seen.desc())
            .first()
        )

        gap = SESSION_GAP_SEC + 1
        if latest and latest.last_seen:
            last_seen = latest.last_seen
            if last_seen.tzinfo is None:
                last_seen = last_seen.replace(tzinfo=datetime.timezone.utc)
            gap = (now - last_seen).total_seconds()
            
            # Force a new session if the calendar day has changed in local time (or UTC)
            if latest.date != now.date():
                gap = SESSION_GAP_SEC + 1

        if gap > SESSION_GAP_SEC:
            # ── New session ────────────────────────────────────────────────
            staff = db.query(models.Staff).filter(models.Staff.name == name).first()
            record = models.Attendance(
                staff_id    = staff.id if staff else None,
                staff_name  = name,
                confidence  = score,
                date        = now.date(),
                entry_time  = now,
                last_seen   = now,
                exit_time   = None,
                camera_id   = camera_id,
                camera_name = camera_name,
            )
            db.add(record)
            db.commit()
            cam_label = f"  @ {camera_name}" if camera_name else ""
            print(f"[Attendance] ✅ New session — {name}  ({score:.0%}){cam_label}  entry: {now.strftime('%H:%M')}")

            # Emit attendance event
            event_engine.publish_event(
                event_type="Attendance",
                camera_id=camera_id,
                camera_name=camera_name,
                confidence=score,
                details={"staff_name": name, "status": "check_in", "has_mask": kwargs.get("has_mask", True)}
            )
            return True
        else:
            # ── Update last_seen on open session ───────────────────────────
            if latest.camera_id != camera_id:
                event_engine.publish_event(
                    event_type="AreaTransition",
                    camera_id=camera_id,
                    camera_name=camera_name,
                    confidence=score,
                    details={"staff_name": name, "from_camera": latest.camera_name, "to_camera": camera_name}
                )
                latest.camera_id = camera_id
                latest.camera_name = camera_name

            latest.last_seen = now
            db.commit()
            
            # Emit update event so UI refreshes last_seen time
            event_engine.publish_event(
                event_type="Attendance",
                camera_id=camera_id,
                camera_name=camera_name,
                confidence=score,
                details={"staff_name": name, "status": "update", "has_mask": kwargs.get("has_mask", True)}
            )
            return False

    except Exception as e:
        print(f"[Attendance] Error for {name}: {e}")
        db.rollback()
        return False
    finally:
        db.close()
