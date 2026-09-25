"""Regression test for _update_human_tracks's centroid matching in
camera/vision_service_zones.py.

Bug (found via /investigate 2026-09-24): tracks were matched against each
other's raw LAST-SEEN centroid with a flat 220px gate. `_frame_count` only
increments once per AI-SAMPLED frame (every 2nd/3rd real capture frame per
ai_sample_interval), so a person moving briskly between two processed
frames could easily exceed 220px of on-screen displacement. When that
happened, no existing track fell inside the gate, a brand-new (unconfirmed,
"Unknown") track_id got minted, and the person was visibly mislabeled
despite recognition itself never failing.

Fix: predict each track's expected position from its last observed
velocity, extrapolated by however many processed frames have elapsed since
it was last seen, and match against that predicted position with a gate
that scales with elapsed frames.

Pure logic test - no model load, no camera frames - _update_human_tracks
only touches bbox/centroid bookkeeping. `process_frame` increments
_frame_count immediately before calling _update_human_tracks (see
vision_service_zones.py), so these tests replicate that ordering manually
instead of going through the full frame pipeline.
"""
from camera.vision_service_zones import VisionServiceZones


def _bbox_at(cx, cy, half_w=40, half_h=60):
    return [cx - half_w, cy - half_h, cx + half_w, cy + half_h]


def _next_frame(service, detections):
    service._frame_count += 1
    return service._update_human_tracks(detections)


def test_fast_linear_movement_keeps_the_same_track_id():
    service = VisionServiceZones(camera_name="test")

    # Frame 1: person at (100, 100). No velocity history yet, so this
    # track's first association still relies on the flat base gate - same
    # as before the fix, and unavoidable with zero prior motion samples.
    tracks = _next_frame(service, [{"bbox": _bbox_at(100, 100)}])
    tid = tracks[0]["track_id"]

    # Frame 2: moved 200px right (within the 220px base gate) - this
    # establishes a ~200px/frame rightward velocity for the track.
    tracks = _next_frame(service, [{"bbox": _bbox_at(300, 100)}])
    assert tracks[0]["track_id"] == tid

    # Frame 3: kept moving at roughly that velocity, landing at (610, 100).
    # That's 310px from the last raw centroid (300, 100) - beyond the OLD
    # flat 220px gate, which matched against the stale last-seen position
    # and would have minted a new "Unknown" track here. It's only 110px
    # from the VELOCITY-PREDICTED position (500, 100), well inside the
    # gate, so the fixed algorithm correctly continues the same track.
    tracks = _next_frame(service, [{"bbox": _bbox_at(610, 100)}])
    assert tracks[0]["track_id"] == tid, (
        "continued motion consistent with the track's established velocity "
        "should keep the same track_id even though raw displacement from "
        "the last-seen position exceeds the flat base gate"
    )


def test_a_second_person_entering_far_away_still_gets_a_new_track():
    service = VisionServiceZones(camera_name="test")

    tracks = _next_frame(service, [{"bbox": _bbox_at(100, 100)}])
    tid_a = tracks[0]["track_id"]

    # A second, unrelated person appears far from the first - must NOT be
    # folded into the first person's track just because the gate widened.
    tracks = _next_frame(service, [
        {"bbox": _bbox_at(120, 100)},   # person A, small drift
        {"bbox": _bbox_at(900, 700)},   # person B, brand new
    ])
    tids = {t["track_id"] for t in tracks}
    assert tid_a in tids
    assert len(tids) == 2, "an unrelated far-away detection must get its own track"


def test_track_gate_widens_after_a_missed_frame():
    service = VisionServiceZones(camera_name="test")

    tracks = _next_frame(service, [{"bbox": _bbox_at(100, 100)}])
    tid = tracks[0]["track_id"]

    # Frame 2: this person's face wasn't detected at all (occlusion/turn) -
    # only report an unrelated detection to advance _frame_count without
    # touching the first track.
    _next_frame(service, [{"bbox": _bbox_at(900, 700)}])

    # Frame 3: person A reappears, having moved further while unseen for
    # two processed frames - the gate must have widened accordingly rather
    # than staying pinned to the single-frame radius.
    tracks = _next_frame(service, [
        {"bbox": _bbox_at(430, 100)},
        {"bbox": _bbox_at(900, 700)},
    ])
    reappeared = next(t for t in tracks if t["bbox"][0] == _bbox_at(430, 100)[0])
    assert reappeared["track_id"] == tid
