"""Regression test for the identity-confirmation streak in
camera/vision_service_zones.py's process_frame().

Bug (found via /investigate 2026-09-14): once a track was confirmed as one
staff member, a *different* person taking over the same track_id could
never be corrected - the "fast recheck" path that lets a new candidate
build its confirmation streak was gated on the track being unconfirmed,
but a confirmed track stays "confirmed" (showing the stale identity) right
up until the moment the new candidate's streak actually completes. That
made the periodic recheck interval (IDENTITY_REFRESH_FRAMES) restart on
every single mismatched sample, so the track could get stuck indefinitely.

This uses two real staff enrollment photos (already in uploads/staff/) and
a real InsightFace model load - no mocks - since the bug is specifically
about the interaction between detection scheduling and the confirmation
streak, not something a pure-logic mock would reproduce faithfully.
"""
import glob

import cv2
import numpy as np
import pytest

from camera.vision_service_zones import VisionServiceZones
from camera.model_manager import ModelManager


def _first_two_staff_photos():
    photos = sorted(glob.glob("uploads/staff/*_front.jpg"))
    if len(photos) < 2:
        pytest.skip("need at least 2 staff enrollment photos in uploads/staff/")
    return photos[0], photos[1]


def test_confirmed_track_corrects_when_a_different_person_takes_over():
    photo_a, photo_b = _first_two_staff_photos()

    service = VisionServiceZones(camera_name="test")
    emb_a = service.extract_embedding(photo_a)
    emb_b = service.extract_embedding(photo_b)
    assert emb_a is not None and emb_b is not None, "could not embed test photos"

    service.update_staff_embeddings([
        {"id": 101, "name": "Staff A", "embedding": emb_a.tolist()},
        {"id": 102, "name": "Staff B", "embedding": emb_b.tolist()},
    ])

    frame_a = cv2.imread(photo_a)
    frame_b_raw = cv2.imread(photo_b)

    app = ModelManager().get_face_analysis(service.config)
    bboxes_b, _ = app.det_model.detect(frame_b_raw, max_num=0, metric="default")
    bx1, by1, bx2, by2 = map(int, bboxes_b[0, 0:4])
    face_b_crop = frame_b_raw[by1:by2, bx1:bx2]

    bboxes_a, _ = app.det_model.detect(frame_a, max_num=0, metric="default")
    ax1, ay1, ax2, ay2 = map(int, bboxes_a[0, 0:4])

    # Transplant B's face into A's frame at A's own face location, so the
    # centroid tracker keeps assigning the SAME track_id across the swap -
    # this is what makes the bug reproducible (a fresh track_id would just
    # go through the normal fast first-confirmation path).
    face_b_resized = cv2.resize(face_b_crop, (ax2 - ax1, ay2 - ay1))
    frame_swapped = frame_a.copy()
    frame_swapped[ay1:ay2, ax1:ax2] = face_b_resized

    # Lock the track onto Staff A first. Enrollment photos can contain a
    # second incidental face (e.g. a bystander) that gets its own track_id -
    # track by track_id specifically, not "any track shows staff A", so a
    # coincidental second match elsewhere in the frame can't hide a bug in
    # the track we actually care about.
    track_id = None
    for _ in range(6):
        _, events, *_ = service.process_frame(frame_a, camera_id=1)
        confirmed = [e for e in events if e.get("staff_id") == 101]
        if confirmed:
            track_id = confirmed[0]["tid"]
            break
    assert track_id is not None, "never confirmed Staff A - test setup problem, not the bug under test"

    # Now the same track sees Staff B's face. It must eventually correct -
    # within a bounded number of frames, not "eventually if you wait
    # forever" - IDENTITY_REFRESH_FRAMES (25) for the periodic recheck to
    # fire, plus IDENTITY_CONFIRMATION_STREAK (3) fast frames to confirm.
    # Check the SAME track_id specifically - a second, unrelated face
    # elsewhere in the frame matching staff B doesn't count as a correction.
    corrected = False
    for _ in range(35):
        _, events, *_ = service.process_frame(frame_swapped, camera_id=1)
        this_track = [e for e in events if e.get("tid") == track_id]
        if this_track and this_track[0].get("staff_id") == 102:
            corrected = True
            break

    assert corrected, (
        "track never corrected to Staff B within 35 frames - the "
        "confirmed-track-immune-to-correction bug is back"
    )


def test_new_track_confirms_instantly_on_a_high_confidence_match():
    """Regression test for a flicker bug found immediately after the fix
    above (found via /investigate 2026-09-14, same session): the crude
    centroid tracker in _update_human_tracks hands out a brand new track_id
    on almost any brief occlusion/movement/angle change. Before
    INSTANT_CONFIRM_THRESHOLD existed, a fresh track always had to rebuild
    the full IDENTITY_CONFIRMATION_STREAK from zero even when the very
    first check already matched with near-certainty - so simply walking
    out of frame and back in (a routine, constant occurrence on a live
    camera) made an already-known staff member's name visibly drop to
    "Unknown" for a couple of frames before re-locking. A high-confidence
    single-frame match must now confirm immediately instead.
    """
    photo = sorted(glob.glob("uploads/staff/*_front.jpg"))[0]

    service = VisionServiceZones(camera_name="test")
    emb = service.extract_embedding(photo)
    assert emb is not None, "could not embed test photo"
    service.update_staff_embeddings([{"id": 999, "name": "Dr. Test", "embedding": emb.tolist()}])

    frame = cv2.imread(photo)
    h, w = frame.shape[:2]
    # Shift the frame content >220px (the centroid tracker's match radius)
    # to force a brand-new track_id on reappearance - the same mechanism
    # that fires on ordinary movement/occlusion in a live feed.
    shift_matrix = np.float32([[1, 0, 250], [0, 1, 0]])
    frame_shifted = cv2.warpAffine(
        frame, shift_matrix, (w + 250, h), borderMode=cv2.BORDER_REPLICATE
    )

    # Lock the original track first.
    original_track_id = None
    for _ in range(6):
        _, events, *_ = service.process_frame(frame, camera_id=1)
        confirmed = [e for e in events if e.get("staff_id") == 999]
        if confirmed:
            original_track_id = confirmed[0]["tid"]
            break
    assert original_track_id is not None, "never confirmed Dr. Test - test setup problem"

    # Re-acquire on a brand new track_id - the very first frame must
    # already show the confirmed identity, not "Unknown".
    _, events, *_ = service.process_frame(frame_shifted, camera_id=1)
    assert events, "expected a detection on the shifted frame"
    new_track = [e for e in events if e["tid"] != original_track_id]
    assert new_track, "expected a new track_id after the >220px shift - test setup problem"
    assert new_track[0].get("staff_id") == 999, (
        "new track did not confirm instantly on a high-confidence match - "
        "the re-acquisition flicker bug is back"
    )


def test_re_verified_is_false_on_frames_that_reuse_a_cached_confirmed_identity():
    """Regression test for camera/attendance_service.py's new-session
    confirmation gate (found via /investigate 2026-09-19): once a track is
    confirmed, Step 1.5 only re-embeds it every IDENTITY_REFRESH_FRAMES -
    frames in between just display the cached identity. attendance_service
    needs to tell those apart from a frame where the vision layer actually
    re-checked and got the same answer again, otherwise one bad frame's
    wrong instant-confirm can be echoed as if it were repeated independent
    evidence. The very first (confirming) frame must report
    `re_verified=True`; an immediate follow-up on the same, unchanged frame
    (nothing has happened to force an early recheck) must report
    `re_verified=False`.
    """
    photo = sorted(glob.glob("uploads/staff/*_front.jpg"))[0]

    service = VisionServiceZones(camera_name="test")
    emb = service.extract_embedding(photo)
    assert emb is not None, "could not embed test photo"
    service.update_staff_embeddings([{"id": 999, "name": "Dr. Test", "embedding": emb.tolist()}])

    frame = cv2.imread(photo)

    _, first_events, *_ = service.process_frame(frame, camera_id=1)
    confirmed = [e for e in first_events if e.get("staff_id") == 999]
    assert confirmed, "never confirmed Dr. Test on the first frame - test setup problem"
    assert confirmed[0].get("re_verified") is True, (
        "the confirming frame itself must be marked re_verified"
    )
    track_id = confirmed[0]["tid"]

    _, second_events, *_ = service.process_frame(frame, camera_id=1)
    same_track = [e for e in second_events if e.get("tid") == track_id]
    assert same_track, "expected the same track to persist on an unchanged next frame"
    assert same_track[0].get("re_verified") is False, (
        "a frame that only reused the cached confirmed identity (no fresh "
        "re-embed) must not report re_verified=True - the "
        "attendance-gate false-positive fix relies on this distinction"
    )


def test_unknown_display_is_flagged_pending_while_a_known_candidate_builds(monkeypatch):
    """Regression test for a false unauthorized-entry alert this session's
    IDENTITY_CONFIRMATION_STREAK exposed (found via /investigate
    2026-09-14): camera/worker.py's "Unknown person" alert path starts a
    grace-period timer as soon as a face_event's name is "Unknown", then
    fires an audio alert + unauthorized-entry event once that timer expires
    (UNKNOWN_PERSON_GRACE_PERIOD_SEC). That was a safe assumption when a
    known person's name flipped from Unknown to their real name within a
    single frame - it stopped being safe once recognizing a known person on
    a brand-new track can legitimately take a few checks (and, combined
    with AI frame-sampling intervals, real seconds) to confirm. Without a
    way to tell "still confirming a real candidate" apart from "genuinely
    no match", every known staff member's ordinary recognition window
    started tripping the unauthorized-entry alert.

    This only tests the SIGNAL vision_service_zones.py now exposes
    (`has_pending_match`) that worker.py's alert logic was changed to
    check - worker.py's alert path itself isn't covered here, since it's
    entangled with the live camera loop's DB/websocket/audio dependencies
    and isn't practically unit-testable in isolation.
    """
    photo = sorted(glob.glob("uploads/staff/*_front.jpg"))[0]

    service = VisionServiceZones(camera_name="test")
    emb = service.extract_embedding(photo)
    assert emb is not None, "could not embed test photo"
    service.update_staff_embeddings([{"id": 999, "name": "Dr. Test", "embedding": emb.tolist()}])

    # A self-match against the exact same enrollment crop scores a literal
    # 1.0 (identical embedding vs. itself) - no amount of image noise
    # reliably lands a real photo strictly between REJECTION_THRESHOLD and
    # INSTANT_CONFIRM_THRESHOLD without a lot of fragile tuning. Set the
    # instant-confirm bar above 1.0 (cosine similarity's own ceiling)
    # instead, so this test always exercises the streak-building path
    # regardless of how similar the match is - isolates the
    # has_pending_match signal without depending on image quality at all.
    import camera.vision_service_zones as vsz_module
    monkeypatch.setattr(vsz_module, "INSTANT_CONFIRM_THRESHOLD", 1.1)

    frame = cv2.imread(photo)

    saw_pending_unknown = False
    for _ in range(6):
        _, events, *_ = service.process_frame(frame, camera_id=1)
        for e in events:
            if e.get("name") == "Unknown" and e.get("has_pending_match"):
                saw_pending_unknown = True
            if e.get("staff_id") == 999:
                break
        else:
            continue
        break

    assert saw_pending_unknown, (
        "expected at least one frame where the display was still \"Unknown\" "
        "but has_pending_match was true (a known candidate mid-confirmation) "
        "- either the streak confirmed in 1 frame (test setup problem) or "
        "the has_pending_match signal regressed"
    )


def _motion_blur(img, kernel_size):
    kernel = np.zeros((kernel_size, kernel_size))
    kernel[(kernel_size - 1) // 2, :] = np.ones(kernel_size)
    kernel = kernel / kernel_size
    return cv2.filter2D(img, -1, kernel)


def test_moving_person_confirms_once_a_clear_frame_appears_within_grace_window():
    """Regression test for "camera breaks and says unknown person when the
    user moves" (found via /investigate 2026-09-15). Motion blur strong
    enough to be typical of real walking/turning drops a genuine known
    match's score below REJECTION_THRESHOLD - confirmed directly: the same
    enrollment photo, motion-blurred, scores 0.0 (no match at all) instead
    of ~0.99. Before NO_MATCH_RETRY_GRACE_FRAMES, a track's first "no match
    at all" result immediately switched it to the slow
    UNKNOWN_IDENTITY_RETRY_FRAMES retry interval - meaning a moving known
    person could get stuck displaying "Unknown" for a long time even once
    their face became clear again, because the system had already
    concluded "probably a stranger" and stopped checking often.

    This simulates continuous movement (many blurry frames) followed by a
    momentarily clear one (e.g. the person pauses or turns toward the
    camera) and asserts recognition catches that clear frame - it must not
    still be waiting out a 15-frame backoff from the earlier blurry run.
    """
    photo = sorted(glob.glob("uploads/staff/*_front.jpg"))[0]

    service = VisionServiceZones(camera_name="test")
    emb = service.extract_embedding(photo)
    assert emb is not None, "could not embed test photo"
    service.update_staff_embeddings([{"id": 999, "name": "Dr. Test", "embedding": emb.tolist()}])

    frame = cv2.imread(photo)
    blurred = _motion_blur(frame, 35)

    # Sanity-check the blur actually defeats recognition in isolation -
    # otherwise this test would pass even without the grace-window fix.
    probe = VisionServiceZones(camera_name="probe")
    probe.update_staff_embeddings([{"id": 999, "name": "Dr. Test", "embedding": emb.tolist()}])
    _, probe_events, *_ = probe.process_frame(blurred, camera_id=1)
    assert probe_events and probe_events[0]["staff_id"] is None, (
        "test setup problem: this blur level isn't actually defeating "
        "recognition, so it can't exercise the no-match grace window"
    )

    # 20 continuously-blurry frames (movement), then one clear frame.
    corrected = False
    for _ in range(20):
        service.process_frame(blurred, camera_id=1)
    _, events, *_ = service.process_frame(frame, camera_id=1)
    if events and events[0].get("staff_id") == 999:
        corrected = True

    assert corrected, (
        "known staff member was not recognized on the first clear frame "
        "after 20 blurry (movement-simulating) frames - the no-match grace "
        "window regressed, or a moving person is getting stuck as Unknown "
        "again"
    )


def test_upper_face_fallback_does_not_default_to_the_only_candidate_with_upper_data():
    """Regression test for a real live mislabeling incident (found via
    /investigate 2026-09-15, reproduced against real camera footage): two
    different real people were both tagged with the same identity at
    50-62% confidence. Root cause: only one enrolled staff member had
    upper-face (periocular/eyes-only) embedding data at all. Whenever a
    face's FULL-face score fell below REJECTION_THRESHOLD, the code fell
    back to comparing the periocular region against staff_upper_embeddings_
    matrix - but with only one real (non-zero) row in that matrix, that
    one identity was the only possible winner for ANYONE whose full face
    didn't match, and the periocular signal alone is weak enough that even
    a genuinely different person's eye region cleared the old 0.5 bar.

    Fix: the upper-face fallback now requires at least 2 staff members
    with real upper-face data before it runs at all - with only one
    candidate, there's no real comparison happening, so it must not run.

    This uses two real staff enrollment photos, matching the exact
    degenerate gallery shape from the real incident: one identity with
    upper-face data, one without.
    """
    photo_a, photo_b = _first_two_staff_photos()

    service = VisionServiceZones(camera_name="test")
    emb_b = service.extract_embedding(photo_b)
    assert emb_b is not None, "could not embed test photo B"

    frame_a = cv2.imread(photo_a)
    app = ModelManager().get_face_analysis(service.config)
    bboxes_a, _ = app.det_model.detect(frame_a, max_num=0, metric="default")
    upper_a = service._extract_upper_face_embedding(frame_a, bboxes_a[0, 0:4])
    assert upper_a is not None, "could not extract upper-face embedding for photo A"

    # Staff A is enrolled with a deliberately WRONG full-face embedding (a
    # random vector, uncorrelated with the real photo) but the REAL
    # upper-face embedding extracted from that same photo - so if the
    # upper-face fallback runs on A's own unmodified photo, it will score
    # a near-perfect self-match (~1.0), guaranteed, regardless of blur or
    # threshold tuning. This isolates the >=2-real-candidates GATE itself:
    # full-face is guaranteed to miss (forcing the fallback to be
    # considered), and if the fallback runs at all with only one real
    # candidate, it would obviously win.
    rng = np.random.default_rng(0)
    fake_full_emb = rng.normal(size=512)

    # Staff B has upper-face data (matches the real Dr. Deepak row); staff A
    # does not have REAL upper-face data of its own in this setup - mirrors
    # the exact degenerate shape from the incident: only one identity in
    # the gallery has a real upper-face row.
    service.update_staff_embeddings([
        {"id": 201, "name": "Staff A", "embedding": fake_full_emb.tolist()},
        {"id": 202, "name": "Staff B", "embedding": emb_b.tolist(), "upper_embedding": upper_a.tolist()},
    ])
    assert int(service.staff_has_upper_embedding.sum()) == 1, "test setup problem: expected exactly 1 real upper-face row"

    # Feed A's own, unmodified photo. Full-face score against the
    # deliberately-wrong embedding will be near zero, forcing the
    # upper-face fallback to be considered. Staff B's upper-face row IS A's
    # real upper-face embedding, so if the fallback ran it would score
    # ~1.0 and (wrongly) confirm as Staff B.
    _, events, *_ = service.process_frame(frame_a, camera_id=1)
    assert events, "expected a detection on photo A"
    matched_staff_id = events[0].get("staff_id")

    assert matched_staff_id != 202, (
        "matched to the only candidate with upper-face data even though "
        "that data doesn't actually belong to the person in this frame - "
        "the degenerate single-candidate upper-face fallback bug is back"
    )


def test_confirmed_track_keeps_re_embedding_every_frame_while_attendance_is_pending():
    """Regression test for felt attendance latency (found via /investigate
    2026-09-20): once a track's identity was confirmed, re-embedding backed
    off to once every IDENTITY_REFRESH_FRAMES (25) dispatched frames - but
    attendance_service._maybe_mark_attendance's new-session gate needs a
    SECOND, independent re_verified=True sighting (via
    has_pending_first_sighting) before it will actually write the
    attendance record. With re-embedding throttled to every 25 frames, that
    second sighting didn't arrive until the next periodic recheck - up to
    ~2-4s on GPU/CoreML hardware - even though the person was already
    displaying correctly on screen. Fixed by keeping re-embedding at every
    dispatched frame for a track whose confirmed name has a pending first
    sighting outstanding, regardless of IDENTITY_REFRESH_FRAMES.

    This checks the mechanism directly: after confirming a track, mark its
    name as having a pending first sighting (as attendance_service would),
    then feed many more frames - well past IDENTITY_REFRESH_FRAMES - and
    assert `_last_identity_run` for that track advances on every single
    frame instead of stalling for 25.
    """
    import camera.attendance_service as attendance_service_module

    photo = sorted(glob.glob("uploads/staff/*_front.jpg"))[0]

    service = VisionServiceZones(camera_name="test")
    emb = service.extract_embedding(photo)
    assert emb is not None, "could not embed test photo"
    service.update_staff_embeddings([{"id": 301, "name": "Staff Pending", "embedding": emb.tolist()}])

    frame = cv2.imread(photo)

    # Confirm the track first (a self-match scores ~1.0, instant-confirms).
    track_id = None
    for _ in range(3):
        _, events, *_ = service.process_frame(frame, camera_id=1)
        confirmed = [e for e in events if e.get("staff_id") == 301]
        if confirmed:
            track_id = confirmed[0]["tid"]
            break
    assert track_id is not None, "never confirmed Staff Pending - test setup problem"

    # Simulate attendance_service having started (but not yet corroborated)
    # a new-session pending window for this name, exactly as
    # _maybe_mark_attendance does on the first re_verified sighting.
    with attendance_service_module._pending_first_sighting_lock:
        attendance_service_module._pending_first_sighting["Staff Pending"] = (
            attendance_service_module.datetime.datetime.now(
                tz=attendance_service_module.datetime.timezone.utc
            )
        )
    try:
        # Feed well past IDENTITY_REFRESH_FRAMES (25) worth of frames and
        # confirm the track is re-embedded on every single one - not just
        # every 25th - while the pending sighting remains outstanding.
        stalled = False
        for _ in range(30):
            last_before = service._last_identity_run.get(track_id)
            frame_count_before = service._frame_count
            service.process_frame(frame, camera_id=1)
            if service._last_identity_run.get(track_id) != frame_count_before + 1:
                stalled = True
                break

        assert not stalled, (
            "a confirmed track with a pending attendance corroboration "
            "stopped being re-embedded every frame - the felt attendance "
            "latency bug is back"
        )
    finally:
        with attendance_service_module._pending_first_sighting_lock:
            attendance_service_module._pending_first_sighting.pop("Staff Pending", None)


def test_marginal_cross_person_match_cannot_bypass_the_streak():
    """Regression test for a confirmed live false-accept (/investigate
    2026-09-20): with only 4 staff enrolled on a real deployment, a single
    poorly-lit, side-angle frame of one staff member scored 0.69 against a
    DIFFERENT enrolled person's gallery embedding - above the old
    INSTANT_CONFIRM_THRESHOLD of 0.65 - and that ONE frame instantly
    bypassed IDENTITY_CONFIRMATION_STREAK entirely, writing real
    Attendance/ZoneTransition rows for the wrong person (confirmed via the
    live event log: the same camera/track alternated between both names
    within seconds).

    This constructs a synthetic "impostor" gallery entry at a known cosine
    similarity to a real staff photo's embedding (a blend of the real
    direction and an orthogonal unit vector - `dot(real, blend) == target`
    by construction), so the false-candidate's score is controlled and
    reproducible instead of depending on finding two real photos that
    happen to collide. Targets ~0.70, matching the real incident's 0.69.

    Asserts a track's very FIRST frame at that score does NOT instantly
    confirm - it must build the streak like any other candidate, giving the
    existing streak/correction machinery a chance to reject it instead of
    it being committed as an instant, irreversible identity.
    """
    photo = sorted(glob.glob("uploads/staff/*_front.jpg"))[0]

    service = VisionServiceZones(camera_name="test")
    real_emb = service.extract_embedding(photo)
    assert real_emb is not None, "could not embed test photo"

    # An orthogonal unit vector, so `target * real + sqrt(1-target^2) *
    # orth` is itself unit-norm and has cosine similarity == target against
    # `real` by construction (orth contributes zero to the dot product).
    rng = np.random.default_rng(seed=42)
    random_vec = rng.standard_normal(real_emb.shape).astype(np.float32)
    orth = random_vec - np.dot(random_vec, real_emb) * real_emb
    orth = orth / np.linalg.norm(orth)

    target_similarity = 0.70
    impostor_emb = (
        target_similarity * real_emb
        + np.sqrt(1.0 - target_similarity**2) * orth
    )

    service.update_staff_embeddings([
        {"id": 777, "name": "Impostor", "embedding": impostor_emb.tolist()},
    ])

    from camera.constants.vision_constants import (
        INSTANT_CONFIRM_THRESHOLD,
        REJECTION_THRESHOLD,
    )

    # The actual raw cosine similarity process_frame's Step 1.5 will compute
    # between this photo's live query embedding and the impostor gallery
    # row - computed the same way process_frame does it, so we know exactly
    # what band the constructed score landed in before asserting anything.
    actual_raw_score = float(np.dot(service.staff_embeddings_matrix[0], real_emb))
    # If the small discrepancy between extract_embedding()'s alignment and
    # process_frame's own internal alignment pushed the observed raw score
    # outside the intended marginal band, this test can't validate what it
    # set out to - skip rather than assert something else by accident.
    if not (REJECTION_THRESHOLD <= actual_raw_score < INSTANT_CONFIRM_THRESHOLD):
        pytest.skip(
            f"constructed impostor score {actual_raw_score:.3f} landed outside "
            f"the intended marginal band [{REJECTION_THRESHOLD}, {INSTANT_CONFIRM_THRESHOLD}) "
            "- test setup problem, not the bug under test"
        )

    frame = cv2.imread(photo)
    _, events, *_ = service.process_frame(frame, camera_id=1)
    assert events, "expected a detection on the test photo"

    assert events[0].get("staff_id") != 777, (
        f"a single frame scoring {actual_raw_score:.3f} (below "
        f"INSTANT_CONFIRM_THRESHOLD={INSTANT_CONFIRM_THRESHOLD}) instantly "
        "confirmed a brand-new track as the impostor identity - the "
        "small-gallery false-accept bug is back"
    )
