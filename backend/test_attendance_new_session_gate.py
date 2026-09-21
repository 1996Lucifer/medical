"""Regression test for camera/attendance_service.py's new-session
confirmation gate.

Bug (found via /investigate 2026-09-19): a staff member ("Anamika") was
shown as "Present" in the Staff Attendance panel despite never actually
appearing in the camera feed. The resulting Attendance row had
entry_time == last_seen == exit_time - a single call to
_maybe_mark_attendance(), never repeated, that nonetheless created a full
attendance session. Root cause: vision_service_zones.py's
INSTANT_CONFIRM_THRESHOLD legitimately confirms a *displayed* identity on
one high-confidence frame (protecting real re-lock-after-occlusion UX -
see test_vision_identity_streak.py's
test_new_track_confirms_instantly_on_a_high_confidence_match, which must
keep passing unchanged), but _maybe_mark_attendance() trusted that
single-frame identity just as unconditionally when deciding to WRITE a
brand-new attendance record - with only a couple of people enrolled in a
small hospital's face gallery, a single stray frame scoring just above the
recognition threshold against the wrong person is a real, observed risk.

Fix: creating a brand-new session (no existing open one) now requires the
same name to be reported a second time, genuinely separated in wall time,
before it's ever written. Updating an already-open session (a real,
ongoing presence) is completely unaffected by this gate.

These tests exercise the gate in isolation - `_upsert_attendance_session`
and the DB layer are stubbed out, since the gate's logic is independent of
what happens once it decides to let a write through.
"""
import datetime

import pytest

import camera.attendance_service as attendance_service
from camera.attendance_service import _maybe_mark_attendance


@pytest.fixture(autouse=True)
def _reset_module_state(monkeypatch):
    # These are module-level dicts the gate mutates - each test needs a
    # clean slate regardless of execution order.
    monkeypatch.setattr(attendance_service, "_pending_first_sighting", {})
    monkeypatch.setattr(attendance_service, "_last_db_write", {})
    # No real DB access in any of these tests - _find_open_session and
    # SessionLocal are stubbed per-test as needed.
    monkeypatch.setattr(attendance_service, "start_auto_checkout_loop", lambda: None)
    monkeypatch.setattr(attendance_service, "SessionLocal", lambda: _DummyDb())


class _DummyDb:
    def query(self, *a, **k):
        return self

    def filter(self, *a, **k):
        return self

    def first(self):
        return None

    def rollback(self):
        pass

    def close(self):
        pass


def _stub_upsert(monkeypatch):
    calls = []

    def fake_upsert(db, now, **kwargs):
        calls.append(kwargs)
        return True

    monkeypatch.setattr(attendance_service, "_upsert_attendance_session", fake_upsert)
    return calls


def test_a_single_isolated_sighting_never_creates_a_session(monkeypatch):
    """Reproduces the exact bug: one high-confidence frame for a name with
    no open session, never repeated, must not create an Attendance row."""
    monkeypatch.setattr(attendance_service, "_find_open_session", lambda *a, **k: None)
    calls = _stub_upsert(monkeypatch)

    result = _maybe_mark_attendance("Anamika", 0.708, camera_id=1, camera_name="Camera 1")

    assert result is False
    assert calls == [], "a single unconfirmed sighting must never write an attendance session"
    assert "Anamika" in attendance_service._pending_first_sighting


def test_a_second_sighting_too_soon_still_does_not_confirm(monkeypatch):
    """A second call arriving well under NEW_SESSION_MIN_SIGHTING_GAP_SEC
    after the first is treated as the same frame batch re-dispatching, not
    genuine corroboration."""
    monkeypatch.setattr(attendance_service, "_find_open_session", lambda *a, **k: None)
    calls = _stub_upsert(monkeypatch)

    now = datetime.datetime.now(tz=datetime.timezone.utc)
    attendance_service._pending_first_sighting["Anamika"] = now - datetime.timedelta(
        seconds=attendance_service.NEW_SESSION_MIN_SIGHTING_GAP_SEC / 2
    )

    result = _maybe_mark_attendance("Anamika", 0.708, camera_id=1, camera_name="Camera 1")

    assert result is False
    assert calls == []


def test_a_genuinely_separated_second_sighting_confirms_the_session(monkeypatch):
    """The corroboration case: the same name reported again, properly
    separated in time, within the confirmation window - a real visit."""
    monkeypatch.setattr(attendance_service, "_find_open_session", lambda *a, **k: None)
    calls = _stub_upsert(monkeypatch)

    now = datetime.datetime.now(tz=datetime.timezone.utc)
    attendance_service._pending_first_sighting["Anamika"] = now - datetime.timedelta(
        seconds=attendance_service.NEW_SESSION_MIN_SIGHTING_GAP_SEC + 1
    )

    result = _maybe_mark_attendance("Anamika", 0.708, camera_id=1, camera_name="Camera 1")

    assert result is True
    assert len(calls) == 1
    assert calls[0]["staff_name"] == "Anamika"
    assert "Anamika" not in attendance_service._pending_first_sighting


def test_a_stale_pending_sighting_restarts_the_window_instead_of_confirming(monkeypatch):
    """If the second sighting arrives too long after the first (beyond
    NEW_SESSION_CONFIRM_WINDOW_SEC), the original sighting has effectively
    expired - this must restart the pending window, not confirm on a
    stale first sighting."""
    monkeypatch.setattr(attendance_service, "_find_open_session", lambda *a, **k: None)
    calls = _stub_upsert(monkeypatch)

    now = datetime.datetime.now(tz=datetime.timezone.utc)
    attendance_service._pending_first_sighting["Anamika"] = now - datetime.timedelta(
        seconds=attendance_service.NEW_SESSION_CONFIRM_WINDOW_SEC + 5
    )

    result = _maybe_mark_attendance("Anamika", 0.708, camera_id=1, camera_name="Camera 1")

    assert result is False
    assert calls == []
    # Restarted, not left stale or cleared outright.
    assert "Anamika" in attendance_service._pending_first_sighting


def test_a_cached_echo_of_the_same_bad_frame_cannot_manufacture_a_second_sighting(monkeypatch):
    """Reproduces the second variant of the bug: vision_service_zones.py
    calls _maybe_mark_attendance every frame with whatever identity is
    CACHED on a track, not just when it's actually re-verified. Without
    filtering those out, one bad frame's wrong instant-confirm gets echoed
    across many subsequent calls, each spaced apart in wall time -
    trivially satisfying a gate that only checks time gaps. re_verified
    distinguishes "fresh evidence" from "echo of the same old evidence"."""
    monkeypatch.setattr(attendance_service, "_find_open_session", lambda *a, **k: None)
    calls = _stub_upsert(monkeypatch)

    # First, genuine piece of evidence.
    result1 = _maybe_mark_attendance(
        "Anamika", 0.708, camera_id=1, camera_name="Camera 1", re_verified=True
    )
    assert result1 is False
    assert "Anamika" in attendance_service._pending_first_sighting

    # Many subsequent frames just echo the same cached (wrong) identity
    # without the vision layer having re-checked it - none of these may
    # count toward confirmation, no matter how many or how spaced apart.
    now = datetime.datetime.now(tz=datetime.timezone.utc)
    for i in range(5):
        attendance_service._pending_first_sighting["Anamika"] = now - datetime.timedelta(
            seconds=attendance_service.NEW_SESSION_MIN_SIGHTING_GAP_SEC + 1
        )
        result = _maybe_mark_attendance(
            "Anamika", 0.708, camera_id=1, camera_name="Camera 1", re_verified=False
        )
        assert result is False

    assert calls == [], "echoed (non-re_verified) frames must never confirm a new session"


def test_updating_an_already_open_session_bypasses_the_gate_entirely(monkeypatch):
    """A genuinely ongoing presence (an existing open session) must never
    be delayed by this gate - only brand-new session creation waits for
    corroboration."""
    monkeypatch.setattr(attendance_service, "_find_open_session", lambda *a, **k: object())
    calls = _stub_upsert(monkeypatch)

    result = _maybe_mark_attendance("Dr. Deepak", 0.658, camera_id=1, camera_name="Camera 1")

    assert result is True
    assert len(calls) == 1
    assert "Dr. Deepak" not in attendance_service._pending_first_sighting
