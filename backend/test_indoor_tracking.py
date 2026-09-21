"""Unit tests for the indoor-tracking fusion + gating engines. Pure
functions, no DB/app context needed."""
import datetime

from indoor_tracking import fusion, gating


# ── fusion.py ────────────────────────────────────────────────────────────

def test_camera_seen_candidate_decays_over_time():
    fresh = fusion.camera_seen_candidate(
        camera_x=1, camera_y=2, floor_id=1, coverage_radius_m=5, seconds_since_seen=0,
    )
    stale = fusion.camera_seen_candidate(
        camera_x=1, camera_y=2, floor_id=1, coverage_radius_m=5, seconds_since_seen=55,
    )
    expired = fusion.camera_seen_candidate(
        camera_x=1, camera_y=2, floor_id=1, coverage_radius_m=5, seconds_since_seen=120,
    )
    assert fresh.confidence > stale.confidence
    assert expired is None


def test_wifi_candidate_single_ap_no_rssi():
    known_aps = [{"bssid": "AA:1", "x": 10, "y": 20, "floor_id": 2, "coverage_radius_m": 8}]
    c = fusion.wifi_candidate(known_aps=known_aps, readings=[{"bssid": "AA:1", "rssi": None}])
    assert c.source == "wifi_single"
    assert (c.x, c.y, c.floor_id) == (10, 20, 2)


def test_wifi_candidate_unknown_bssid_returns_none():
    known_aps = [{"bssid": "AA:1", "x": 10, "y": 20, "floor_id": 2, "coverage_radius_m": 8}]
    c = fusion.wifi_candidate(known_aps=known_aps, readings=[{"bssid": "ZZ:9", "rssi": -70}])
    assert c is None


def test_wifi_candidate_multi_ap_trilateration_between_aps():
    known_aps = [
        {"bssid": "AA:1", "x": 0, "y": 0, "floor_id": 1, "coverage_radius_m": 8},
        {"bssid": "AA:2", "x": 10, "y": 0, "floor_id": 1, "coverage_radius_m": 8},
    ]
    readings = [{"bssid": "AA:1", "rssi": -50}, {"bssid": "AA:2", "rssi": -50}]
    c = fusion.wifi_candidate(known_aps=known_aps, readings=readings)
    assert c.source == "wifi_trilateration"
    assert 0 < c.x < 10  # equal signal -> roughly midway
    assert abs(c.y) < 1e-6


def test_gps_candidate_none_without_floor_calibration():
    c = fusion.gps_candidate(
        lat=1.0, lng=1.0, gps_accuracy_m=10, floor_id=1,
        origin_lat=None, origin_lng=None, geo_rotation_deg=None, meters_per_unit=None,
    )
    assert c is None


def test_gps_candidate_confidence_capped_low():
    c = fusion.gps_candidate(
        lat=1.0001, lng=1.0001, gps_accuracy_m=5, floor_id=1,
        origin_lat=1.0, origin_lng=1.0, geo_rotation_deg=0.0, meters_per_unit=1.0,
    )
    assert c is not None
    assert c.confidence <= fusion.GPS_MAX_CONFIDENCE


def test_fuse_single_candidate_passthrough():
    c = fusion.Candidate(x=5, y=5, floor_id=1, accuracy_m=3, confidence=0.8, source="camera")
    fused = fusion.fuse([c])
    assert (fused.x, fused.y, fused.confidence) == (5, 5, 0.8)


def test_fuse_agreeing_candidates_weighted_average():
    a = fusion.Candidate(x=0, y=0, floor_id=1, accuracy_m=5, confidence=0.9, source="camera")
    b = fusion.Candidate(x=2, y=0, floor_id=1, accuracy_m=5, confidence=0.5, source="wifi_single")
    fused = fusion.fuse([a, b])
    # Weighted toward the higher-confidence candidate (camera), not the midpoint.
    assert 0 < fused.x < 1
    assert "camera" in fused.source and "wifi_single" in fused.source


def test_fuse_disagreeing_candidates_trusts_strongest_and_lowers_confidence():
    strong = fusion.Candidate(x=0, y=0, floor_id=1, accuracy_m=5, confidence=0.9, source="camera")
    far_weak = fusion.Candidate(x=50, y=50, floor_id=1, accuracy_m=20, confidence=0.3, source="gps")
    fused = fusion.fuse([strong, far_weak])
    assert (fused.x, fused.y) == (0, 0)
    assert fused.confidence < strong.confidence
    assert fused.source == "camera"


def test_fuse_empty_returns_none():
    assert fusion.fuse([]) is None
    assert fusion.fuse([None, None]) is None


def test_snap_to_nearest_room_inside_stays_put():
    rooms = [{"name": "Pharmacy", "polygon": [(0, 0), (10, 0), (10, 10), (0, 10)]}]
    x, y, name = fusion.snap_to_nearest_room(5, 5, rooms)
    assert (x, y, name) == (5, 5, "Pharmacy")


def test_snap_to_nearest_room_outside_snaps_to_boundary():
    rooms = [{"name": "Pharmacy", "polygon": [(0, 0), (10, 0), (10, 10), (0, 10)]}]
    x, y, name = fusion.snap_to_nearest_room(15, 5, rooms)
    assert name == "Pharmacy"
    assert x == 10  # snapped onto the right edge
    assert y == 5


def test_snap_to_nearest_room_no_rooms_passthrough():
    x, y, name = fusion.snap_to_nearest_room(3, 4, [])
    assert (x, y, name) == (3, 4, None)


def test_smooth_no_previous_point_passthrough():
    x, y = fusion.smooth(10, 10, None, None)
    assert (x, y) == (10, 10)


def test_smooth_moves_toward_new_point_gradually():
    x, y = fusion.smooth(10, 0, 0, 0, alpha=0.4)
    assert x == 4.0  # 0.4*10 + 0.6*0
    assert y == 0.0


# ── gating.py ────────────────────────────────────────────────────────────

HOSPITAL_SQUARE = [(0, 0), (0, 1), (1, 1), (1, 0)]  # lat/lng unit square


def test_gating_stopped_when_session_closed():
    status = gating.decide_status(
        attendance_session_open=False, gps=None, matched_known_wifi_ap=False,
        geofence_polygon=HOSPITAL_SQUARE, now=datetime.datetime.now(),
        working_hours_start=None, working_hours_end=None,
    )
    assert status == "stopped"


def test_gating_active_without_geofence_configured():
    status = gating.decide_status(
        attendance_session_open=True, gps={"lat": 99, "lng": 99}, matched_known_wifi_ap=False,
        geofence_polygon=None, now=datetime.datetime.now(),
        working_hours_start=None, working_hours_end=None,
    )
    assert status == "active"


def test_gating_active_when_known_wifi_ap_matches_even_if_gps_missing():
    status = gating.decide_status(
        attendance_session_open=True, gps=None, matched_known_wifi_ap=True,
        geofence_polygon=HOSPITAL_SQUARE, now=datetime.datetime.now(),
        working_hours_start=None, working_hours_end=None,
    )
    assert status == "active"


def test_gating_paused_when_outside_geofence_during_working_hours():
    now = datetime.datetime.combine(datetime.date.today(), datetime.time(12, 0))
    status = gating.decide_status(
        attendance_session_open=True, gps={"lat": 5, "lng": 5}, matched_known_wifi_ap=False,
        geofence_polygon=HOSPITAL_SQUARE, now=now,
        working_hours_start=datetime.time(9, 0), working_hours_end=datetime.time(17, 0),
    )
    assert status == "paused_outside_geofence"


def test_gating_resumes_active_when_back_inside_geofence():
    now = datetime.datetime.combine(datetime.date.today(), datetime.time(12, 0))
    status = gating.decide_status(
        attendance_session_open=True, gps={"lat": 0.5, "lng": 0.5}, matched_known_wifi_ap=False,
        geofence_polygon=HOSPITAL_SQUARE, now=now,
        working_hours_start=datetime.time(9, 0), working_hours_end=datetime.time(17, 0),
        previous_status="paused_outside_geofence",
    )
    assert status == "active"


def test_gating_stopped_when_outside_geofence_after_working_hours():
    now = datetime.datetime.combine(datetime.date.today(), datetime.time(20, 0))
    status = gating.decide_status(
        attendance_session_open=True, gps={"lat": 5, "lng": 5}, matched_known_wifi_ap=False,
        geofence_polygon=HOSPITAL_SQUARE, now=now,
        working_hours_start=datetime.time(9, 0), working_hours_end=datetime.time(17, 0),
    )
    assert status == "stopped"


def test_gating_holds_previous_status_with_no_evidence():
    status = gating.decide_status(
        attendance_session_open=True, gps=None, matched_known_wifi_ap=False,
        geofence_polygon=HOSPITAL_SQUARE, now=datetime.datetime.now(),
        working_hours_start=None, working_hours_end=None,
        previous_status="paused_outside_geofence",
    )
    assert status == "paused_outside_geofence"


def test_working_hours_overnight_window():
    assert gating.is_within_working_hours(
        datetime.time(23, 0), datetime.time(22, 0), datetime.time(6, 0)
    )
    assert gating.is_within_working_hours(
        datetime.time(3, 0), datetime.time(22, 0), datetime.time(6, 0)
    )
    assert not gating.is_within_working_hours(
        datetime.time(12, 0), datetime.time(22, 0), datetime.time(6, 0)
    )
