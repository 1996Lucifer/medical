import datetime
import threading
from typing import Optional

from database import SessionLocal
import models
from events import event_engine
from indoor_tracking.hub import hub

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

# A brand-new attendance session requires the SAME name to be reported a
# second time, genuinely separated in wall time, before it's ever written -
# see the comment on _maybe_mark_attendance below for why. {name: datetime
# of the first, still-unconfirmed sighting}.
NEW_SESSION_MIN_SIGHTING_GAP_SEC = 1.0
NEW_SESSION_CONFIRM_WINDOW_SEC = 10.0
_pending_first_sighting: dict = {}
_pending_first_sighting_lock = threading.Lock()


def has_pending_first_sighting(name: str) -> bool:
    """
    True while `name` has an unconfirmed first sighting waiting on the
    second, independent re-embed required to open a new session (see
    _maybe_mark_attendance below).

    vision_service_zones.py calls this to decide whether to keep
    re-embedding an already-identity-confirmed track every dispatched
    frame instead of backing off to the slow IDENTITY_REFRESH_FRAMES
    cadence. Without it, that corroborating second sighting doesn't
    arrive until the next periodic recheck (up to IDENTITY_REFRESH_FRAMES
    dispatched frames later - ~2-4s on GPU/CoreML hardware), so a person
    who is already confirmed on-screen still visibly waits several
    seconds before attendance is actually marked (/investigate
    2026-09-20). Once this returns False (corroborated or expired),
    re-embedding correctly falls back to the normal cadence.
    """
    with _pending_first_sighting_lock:
        return name in _pending_first_sighting


def _as_utc(dt: Optional[datetime.datetime]) -> Optional[datetime.datetime]:
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=datetime.timezone.utc)
    return dt.astimezone(datetime.timezone.utc)


def checkout_session(
    db, record: "models.Attendance", now: datetime.datetime, reason: str
) -> None:
    """
    The one shared "close this attendance session" procedure - sets
    exit_time, drops the in-memory throttle/hub state, and publishes the
    same event every checkout path already published. Used by the manual
    checkout endpoint, the 15-minute-unseen auto-checkout scan below, and
    the geofence+shift-based auto-checkout in
    routers/indoor_tracking.py's /signal handler - one place these three
    call sites agree on what "checked out" means, instead of three copies
    of the same four lines. Caller owns db.commit().
    """
    if record.exit_time is not None:
        return  # already checked out - avoid double-publishing the event
    record.exit_time = now
    with _last_db_write_lock:
        _last_db_write.pop(record.staff_name, None)
    hub.stop_session(record.id)
    event_engine.publish_event(
        event_type="Attendance",
        camera_id=record.camera_id,
        camera_name=record.camera_name,
        confidence=record.confidence,
        details={
            "staff_name": record.staff_name,
            "status": "auto_check_out" if reason != "manual" else "check_out",
            "reason": reason,
            "last_seen": (_as_utc(record.last_seen) or now).isoformat(),
        },
    )


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
            checkout_session(db, record, last_seen, reason="not_seen_timeout")
            closed_count += 1

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

def _feed_camera_seen_signal(db, attendance_id: int, camera_id: Optional[int], now: datetime.datetime) -> None:
    """
    Feed a fresh camera-seen positioning candidate into the indoor-tracking
    hub. A face-recognition detection is strong, immediate evidence of
    presence, so this bypasses geofence gating entirely (being seen by an
    on-site camera already proves the person is on the hospital premises)
    and always reports status="active".
    """
    if camera_id is None or not hub.is_active(attendance_id):
        return
    from indoor_tracking import fusion
    from indoor_tracking.floor_cache import get_camera_position_cached, get_room_dicts_cached

    camera_position = get_camera_position_cached(db, camera_id)
    if camera_position is None:
        return
    floor_id, camera_x, camera_y, coverage_radius_m = camera_position

    candidate = fusion.camera_seen_candidate(
        camera_x=camera_x, camera_y=camera_y, floor_id=floor_id,
        coverage_radius_m=coverage_radius_m, seconds_since_seen=0.0,
    )
    if candidate is None:
        return

    state = hub.get_session(attendance_id)
    x, y = fusion.smooth(
        candidate.x, candidate.y,
        state.x if state else None, state.y if state else None,
    )

    room_dicts = get_room_dicts_cached(db, floor_id)
    x, y, area_name = fusion.snap_to_nearest_room(x, y, room_dicts)

    hub.update_position(
        attendance_id, floor_id=floor_id, x=x, y=y, area_name=area_name,
        accuracy_m=candidate.accuracy_m, confidence=candidate.confidence,
        source="camera", status="active",
    )


def _find_open_session(
    db, *, staff_id: Optional[int] = None, staff_name: Optional[str] = None
) -> Optional["models.Attendance"]:
    """Most recent still-open (exit_time IS NULL) session, matched by
    staff_id when known (RFID path) or by staff_name (face path, kept
    exactly as before — face recognition never had a staff_id up front)."""
    q = db.query(models.Attendance).filter(models.Attendance.exit_time.is_(None))
    if staff_id is not None:
        q = q.filter(models.Attendance.staff_id == staff_id)
    else:
        q = q.filter(models.Attendance.staff_name == staff_name)
    return q.order_by(models.Attendance.last_seen.desc()).first()


def _upsert_attendance_session(
    db,
    now: datetime.datetime,
    *,
    staff_id: Optional[int],
    staff_name: str,
    confidence: Optional[float],
    camera_id: Optional[int],
    camera_name: Optional[str],
    source: str,
    has_mask: bool = True,
    match_by_staff_id: bool = False,
) -> bool:
    """
    Shared session logic behind both `_maybe_mark_attendance` (face
    recognition, name+score keyed) and `mark_attendance_for_staff` (RFID,
    staff_id keyed) — this is the one place that decides "new session vs.
    update existing session" and publishes the corresponding events, so the
    two channels can never drift out of sync with each other.

    1. Look up the most recent OPEN Attendance record for this person.
    2. If NO record exists OR last_seen > SESSION_GAP_SEC ago (or the
       calendar day changed) → create a NEW session (entry_time = now).
    3. Otherwise → update last_seen on the existing open session.
       (exit_time is set manually or by automatic stale-session checkout.)

    Returns True if a new session was created, False if an existing one was
    just touched. Caller owns the db session (commit/rollback/close).
    """
    auto_checkout_stale_sessions(now)

    latest = _find_open_session(
        db,
        staff_id=staff_id if match_by_staff_id else None,
        staff_name=None if match_by_staff_id else staff_name,
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
        record = models.Attendance(
            staff_id=staff_id,
            staff_name=staff_name,
            confidence=confidence,
            date=now.date(),
            entry_time=now,
            last_seen=now,
            exit_time=None,
            camera_id=camera_id,
            camera_name=camera_name,
            source=source,
        )
        db.add(record)
        db.commit()

        department = record.staff.category if record.staff else None
        hub.start_session(record.id, staff_id, staff_name, department)
        _feed_camera_seen_signal(db, record.id, camera_id, now)

        cam_label = f"  @ {camera_name}" if camera_name else ""
        conf_label = f"  ({confidence:.0%})" if confidence is not None else ""
        print(
            f"[Attendance] ✅ New session ({source}) — {staff_name}{conf_label}"
            f"{cam_label}  entry: {now.strftime('%H:%M')}"
        )

        event_engine.publish_event(
            event_type="Attendance",
            camera_id=camera_id,
            camera_name=camera_name,
            confidence=confidence,
            details={
                "staff_name": staff_name,
                "status": "check_in",
                "has_mask": has_mask,
                "source": source,
            },
        )
        return True
    else:
        # ── Update last_seen on open session ───────────────────────────
        if latest.camera_id != camera_id:
            event_engine.publish_event(
                event_type="AreaTransition",
                camera_id=camera_id,
                camera_name=camera_name,
                confidence=confidence,
                details={
                    "staff_name": staff_name,
                    "from_camera": latest.camera_name,
                    "to_camera": camera_name,
                },
            )
            latest.camera_id = camera_id
            latest.camera_name = camera_name

        latest.last_seen = now
        db.commit()

        if hub.is_active(latest.id):
            _feed_camera_seen_signal(db, latest.id, camera_id, now)

        # Emit update event so UI refreshes last_seen time
        event_engine.publish_event(
            event_type="Attendance",
            camera_id=camera_id,
            camera_name=camera_name,
            confidence=confidence,
            details={
                "staff_name": staff_name,
                "status": "update",
                "has_mask": has_mask,
                "source": source,
            },
        )
        return False


def _maybe_mark_attendance(
    name: str, score: float,
    camera_id: Optional[int] = None,
    camera_name: Optional[str] = None,
    re_verified: bool = True,
    **kwargs
):
    """
    Session-aware attendance marking for the face-recognition pipeline.

    1. If last DB write for this person was < LAST_SEEN_FREQ_SEC ago → skip (throttle).
    2. Delegate the actual new-session-vs-update-existing-session decision
       (and event publishing) to `_upsert_attendance_session`, keyed by
       staff_name (unchanged behavior — a face match only has a name+score,
       not a staff_id, until we resolve one below).

    Creating a brand-new session additionally requires a second, genuinely
    independent sighting first (see NEW_SESSION_*_SEC above) - found live
    (/investigate 2026-09-19), two variants of the same underlying bug:

    1. A staff member was marked "Present" from a single frame despite
       never appearing in the feed again (Attendance row had
       entry_time == last_seen == exit_time - one call, never repeated).
    2. After adding a naive "must be reported twice, spaced apart" gate,
       a full MINUTE of a real person's track being mislabeled as someone
       else still created a record - because `_maybe_mark_attendance` is
       called every frame with whatever identity is CURRENTLY CACHED on a
       track, not just when the vision layer actually re-verifies it
       (vision_service_zones.py only re-embeds a confirmed track every
       IDENTITY_REFRESH_FRAMES). One bad frame's wrong instant-confirm got
       echoed across many subsequent frames, trivially satisfying a gate
       that only checked wall-clock spacing between calls.

    Fix: only calls where `re_verified` is True (this frame's identity
    came from an actual fresh re-embed this pass, not a cached echo of an
    earlier frame's result - see vision_service_zones.py's face event
    `re_verified` field) count as evidence at all. A re_verified=False call
    is a no-op for this gate - it neither starts nor advances the pending
    window, so an echoed bad frame can't manufacture a second data point
    out of the same original mistake.

    vision_service_zones.py's INSTANT_CONFIRM_THRESHOLD legitimately
    confirms a *displayed* identity on one high-confidence frame - that's
    protecting real re-lock-after-occlusion UX (see
    test_new_track_confirms_instantly_on_a_high_confidence_match) and must
    keep doing that unchanged. But writing an actual attendance record is
    a stronger claim than what a live overlay shows, and with only a
    couple of people enrolled in a small hospital's face gallery, a stray
    frame scoring just above the recognition threshold against the wrong
    person is a real, observed risk. Updating an EXISTING open session is
    unaffected by this gate - only the create-a-new-session path waits for
    corroboration.
    """
    start_auto_checkout_loop()

    if name == "Unknown":
        now = datetime.datetime.now(tz=datetime.timezone.utc)
        throttle_key = f"unknown_{camera_id}"

        # We don't trigger the actual event here anymore, we let the worker.py handle the grace period!
        # This prevents duplicate alerts since worker.py already checks for Unknown.
        return True

    now = datetime.datetime.now(tz=datetime.timezone.utc)

    db = SessionLocal()
    try:
        if _find_open_session(db, staff_id=None, staff_name=name) is None:
            if not re_verified:
                # Just an echo of an earlier frame's (possibly wrong)
                # result - not new evidence either way. Leave any pending
                # window exactly as it is.
                return False
            with _pending_first_sighting_lock:
                first_seen = _pending_first_sighting.get(name)
                gap = (now - first_seen).total_seconds() if first_seen else None
                if gap is None or gap > NEW_SESSION_CONFIRM_WINDOW_SEC:
                    # First sighting ever, or the previous one expired
                    # unconfirmed - start (or restart) the pending window
                    # rather than creating a session yet.
                    _pending_first_sighting[name] = now
                    return False
                if gap < NEW_SESSION_MIN_SIGHTING_GAP_SEC:
                    # Too soon to count as a genuinely separate sighting -
                    # likely the same frame batch re-dispatching, not a
                    # second independent detection.
                    return False
                del _pending_first_sighting[name]

        # In-memory throttle — skip DB entirely if we wrote recently
        with _last_db_write_lock:
            last_write = _last_db_write.get(name)
            if last_write and (now - last_write).total_seconds() < LAST_SEEN_FREQ_SEC:
                return False
            _last_db_write[name] = now

        staff = db.query(models.Staff).filter(models.Staff.name == name).first()
        return _upsert_attendance_session(
            db,
            now,
            staff_id=staff.id if staff else None,
            staff_name=name,
            confidence=score,
            camera_id=camera_id,
            camera_name=camera_name,
            source="face",
            has_mask=kwargs.get("has_mask", True),
            match_by_staff_id=False,
        )
    except Exception as e:
        print(f"[Attendance] Error for {name}: {e}")
        db.rollback()
        return False
    finally:
        db.close()


def mark_attendance_for_staff(
    db,
    staff_id: int,
    source: str = "rfid",
    camera_id: Optional[int] = None,
    camera_name: Optional[str] = None,
) -> Optional[dict]:
    """
    Staff-id-keyed counterpart to `_maybe_mark_attendance`, for channels
    that already know exactly *which* staff member this is (e.g. an RFID
    badge tap resolved via RfidCard) rather than a face-match name+score.
    Reuses the exact same session/throttle/auto-checkout/event-publish
    logic through `_upsert_attendance_session` — this is a second entry
    point into the same Attendance table/session state, not a parallel
    reimplementation.

    Unlike `_maybe_mark_attendance`, this takes a caller-owned `db` session
    (the FastAPI request's session in routers/rfid.py) rather than opening
    its own — the caller is responsible for the session's lifecycle.

    Returns {"staff_name": ..., "role": ...} on success, or None if
    `staff_id` doesn't resolve to a Staff row.
    """
    start_auto_checkout_loop()
    now = datetime.datetime.now(tz=datetime.timezone.utc)

    staff = db.query(models.Staff).filter(models.Staff.id == staff_id).first()
    if not staff:
        return None

    # Separate throttle namespace (staff_id, not name) so it can never
    # collide with the face-recognition throttle keys above.
    throttle_key = f"staff_id_{staff_id}"
    with _last_db_write_lock:
        last_write = _last_db_write.get(throttle_key)
        throttled = bool(
            last_write and (now - last_write).total_seconds() < LAST_SEEN_FREQ_SEC
        )
        if not throttled:
            _last_db_write[throttle_key] = now

    if not throttled:
        _upsert_attendance_session(
            db,
            now,
            staff_id=staff.id,
            staff_name=staff.name,
            confidence=None,
            camera_id=camera_id,
            camera_name=camera_name,
            source=source,
            match_by_staff_id=True,
        )

    return {"staff_name": staff.name, "role": staff.role or "Medical Staff"}
