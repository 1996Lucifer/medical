"""
Geofence + working-hours gating.

Decides whether tracking should be `active`, `paused_outside_geofence`, or
`stopped` for an incoming signal, BEFORE fusion runs. Pure functions -
DB/time lookups happen in the caller (routers/indoor_tracking.py), which
passes in plain values so this stays unit-testable.
"""
import datetime
import math
from typing import List, Optional, Tuple

Point = Tuple[float, float]  # (lat, lng)


def point_in_geo_polygon(lat: float, lng: float, polygon: List[Point]) -> bool:
    inside = False
    n = len(polygon)
    if n < 3:
        return True  # no real polygon configured - don't gate on it
    j = n - 1
    for i in range(n):
        lat_i, lng_i = polygon[i]
        lat_j, lng_j = polygon[j]
        if ((lng_i > lng) != (lng_j > lng)) and (
            lat < (lat_j - lat_i) * (lng - lng_i) / ((lng_j - lng_i) or 1e-12) + lat_i
        ):
            inside = not inside
        j = i
    return inside


def is_within_working_hours(
    now: datetime.time,
    working_hours_start: Optional[datetime.time],
    working_hours_end: Optional[datetime.time],
) -> bool:
    if working_hours_start is None or working_hours_end is None:
        return True  # not configured - don't gate on it
    if working_hours_start <= working_hours_end:
        return working_hours_start <= now <= working_hours_end
    # overnight shift window, e.g. 22:00 -> 06:00
    return now >= working_hours_start or now <= working_hours_end


def decide_status(
    *,
    attendance_session_open: bool,
    gps: Optional[dict],          # {"lat": .., "lng": ..} or None
    matched_known_wifi_ap: bool,  # a reading matched a WifiAccessPoint row
    geofence_polygon: Optional[List[Point]],
    now: datetime.datetime,
    working_hours_start: Optional[datetime.time],
    working_hours_end: Optional[datetime.time],
    previous_status: str = "active",
) -> str:
    """Returns "active" | "paused_outside_geofence" | "stopped"."""
    if not attendance_session_open:
        return "stopped"

    if not geofence_polygon:
        # No geofence configured for this hospital - can't gate on presence,
        # only the attendance session lifecycle controls tracking.
        return "active"

    if matched_known_wifi_ap:
        # On-site Wi-Fi association is itself strong evidence of being on
        # premises, often more reliable right at the boundary than a noisy
        # GPS fix.
        return "active"

    if gps is not None:
        inside = point_in_geo_polygon(gps["lat"], gps["lng"], geofence_polygon)
        if inside:
            return "active"
        if is_within_working_hours(now.time(), working_hours_start, working_hours_end):
            return "paused_outside_geofence"
        return "stopped"

    # No GPS and no known Wi-Fi match this update - not enough evidence to
    # flip state either way; hold the previous status rather than guessing.
    return previous_status
