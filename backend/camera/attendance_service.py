import datetime
import threading
from typing import Optional

from database import SessionLocal
import models
from events import event_engine

# ── Attendance session constants ──────────────────────────────────────────────
SESSION_GAP_SEC    = 5 * 3600   # 5 hours of absence → new session / new entry
LAST_SEEN_FREQ_SEC = 30         # update last_seen at most every 30 seconds
AUTO_CHECKOUT_AFTER_SEC = 15 * 60  # 15 minutes unseen → automatic checkout
AUTO_CHECKOUT_SCAN_SEC = 60

# Per-person in-memory timestamps (avoids hitting DB on every frame)
_last_db_write: dict   = {}   # {name: datetime} — when we last wrote to DB
_last_db_write_lock = threading.Lock()
_auto_checkout_started = False
_auto_checkout_lock = threading.Lock()


def _as_utc(dt: Optional[datetime.datetime]) -> Optional[datetime.datetime]:
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=datetime.timezone.utc)
    return dt.astimezone(datetime.timezone.utc)


def auto_checkout_stale_sessions(now: Optional[datetime.datetime] = None) -> int:
    """
    Close open staff attendance sessions when the person has not been seen
    for AUTO_CHECKOUT_AFTER_SEC. Attendance is presence-based and zone-independent.
    """
    now = now or datetime.datetime.now(tz=datetime.timezone.utc)
    cutoff = now - datetime.timedelta(seconds=AUTO_CHECKOUT_AFTER_SEC)
    db = SessionLocal()
    closed_count = 0
    try:
        stale_records = (
            db.query(models.Attendance)
            .filter(models.Attendance.exit_time.is_(None))
            .filter(models.Attendance.last_seen.isnot(None))
            .filter(models.Attendance.last_seen < cutoff)
            .all()
        )

        for record in stale_records:
            last_seen = _as_utc(record.last_seen) or now
            record.exit_time = last_seen
            closed_count += 1
            with _last_db_write_lock:
                _last_db_write.pop(record.staff_name, None)

            event_engine.publish_event(
                event_type="Attendance",
                camera_id=record.camera_id,
                camera_name=record.camera_name,
                confidence=record.confidence,
                details={
                    "staff_name": record.staff_name,
                    "status": "auto_check_out",
                    "reason": "not_seen_timeout",
                    "last_seen": last_seen.isoformat(),
                },
            )

        if closed_count:
            db.commit()
            print(f"[Attendance] Auto checked out {closed_count} stale session(s).")
        return closed_count
    except Exception as e:
        print(f"[Attendance] Auto-checkout error: {e}")
        db.rollback()
        return 0
    finally:
        db.close()


def _auto_checkout_loop():
    while True:
        try:
            auto_checkout_stale_sessions()
        except Exception as e:
            print(f"[Attendance] Auto-checkout loop error: {e}")
        finally:
            import time

            time.sleep(AUTO_CHECKOUT_SCAN_SEC)


def start_auto_checkout_loop():
    global _auto_checkout_started
    with _auto_checkout_lock:
        if _auto_checkout_started:
            return
        thread = threading.Thread(target=_auto_checkout_loop, daemon=True)
        thread.start()
        _auto_checkout_started = True

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
       (exit_time is set manually or by automatic stale-session checkout.)
    """
    start_auto_checkout_loop()

    if name == "Unknown":
        now = datetime.datetime.now(tz=datetime.timezone.utc)
        throttle_key = f"unknown_{camera_id}"
        
        # We don't trigger the actual event here anymore, we let the worker.py handle the grace period!
        # This prevents duplicate alerts since worker.py already checks for Unknown.
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
        auto_checkout_stale_sessions(now)

        # Find most recent open attendance record for this person.
        # Closed sessions are never revived; a later sighting starts a new session.
        latest: Optional[models.Attendance] = (
            db.query(models.Attendance)
            .filter(models.Attendance.staff_name == name)
            .filter(models.Attendance.exit_time.is_(None))
            .order_by(models.Attendance.last_seen.desc())
            .first()
        )

        gap = SESSION_GAP_SEC + 1
        if latest and latest.last_seen:
            last_seen = _as_utc(latest.last_seen)
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
