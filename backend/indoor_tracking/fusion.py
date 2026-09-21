"""
Indoor positioning: sensor fusion + map matching.

Combines up to 3 signal types into a single (x, y, floor_id, accuracy_m,
confidence, source) estimate. Every function here is pure / DB-free so it's
directly unit-testable — callers look up Camera/WifiAccessPoint/Floor/Room
rows and pass plain dicts in.

Signals, in the order the product spec ranks them:
  1. camera-seen   - anchored at a Camera's configured (floor_id, x, y),
                      confidence decays with time since last detection.
  2. wifi          - anchored at a WifiAccessPoint's position (single-AP
                      case, the only thing iOS can expose), or a weighted
                      multi-AP estimate when 2+ RSSI readings are available
                      (Android-only in practice).
  3. gps           - converted to floor-local meters via the floor's
                      optional geo-anchor; confidence is explicitly capped
                      low because GPS indoors is unreliable.
"""
import math
import time
from dataclasses import dataclass
from typing import List, Optional, Sequence, Tuple

CAMERA_SEEN_DECAY_SEC = 60.0
CAMERA_SEEN_INITIAL_CONFIDENCE = 0.9
GPS_MAX_CONFIDENCE = 0.4
DISAGREEMENT_THRESHOLD_M = 15.0


@dataclass
class Candidate:
    x: float
    y: float
    floor_id: int
    accuracy_m: float
    confidence: float
    source: str  # "camera" | "wifi_single" | "wifi_trilateration" | "gps"


@dataclass
class FusedPosition:
    x: float
    y: float
    floor_id: int
    accuracy_m: float
    confidence: float
    source: str  # comma-joined list of contributing sources


def camera_seen_candidate(
    *, camera_x: float, camera_y: float, floor_id: int, coverage_radius_m: float,
    seconds_since_seen: float,
) -> Optional[Candidate]:
    if seconds_since_seen < 0:
        seconds_since_seen = 0
    decay = max(0.0, 1.0 - (seconds_since_seen / CAMERA_SEEN_DECAY_SEC))
    confidence = CAMERA_SEEN_INITIAL_CONFIDENCE * decay
    if confidence <= 0.01:
        return None
    return Candidate(
        x=camera_x, y=camera_y, floor_id=floor_id,
        accuracy_m=coverage_radius_m, confidence=confidence, source="camera",
    )


def wifi_candidate(
    *, known_aps: Sequence[dict], readings: Sequence[dict],
) -> Optional[Candidate]:
    """
    known_aps: [{"bssid","x","y","floor_id","coverage_radius_m","tx_power_dbm"}]
    readings:  [{"bssid","rssi"}] — rssi optional (single connected-AP case
               has no scan list, just identity).
    """
    matched = []
    by_bssid = {ap["bssid"]: ap for ap in known_aps}
    for r in readings:
        ap = by_bssid.get(r.get("bssid"))
        if ap:
            matched.append((ap, r.get("rssi")))

    if not matched:
        return None

    if len(matched) == 1 or all(rssi is None for _, rssi in matched):
        ap, _ = matched[0]
        return Candidate(
            x=ap["x"], y=ap["y"], floor_id=ap["floor_id"],
            accuracy_m=ap.get("coverage_radius_m", 8.0), confidence=0.55,
            source="wifi_single",
        )

    # 2+ APs with RSSI: weighted centroid, weight ~ signal strength
    # (closer to 0 dBm = stronger = more weight). This is a simple
    # weighted-centroid estimate, not a full least-squares multilateration
    # solve - adequate given noisy consumer RSSI and few APs in practice.
    total_w = 0.0
    wx = wy = 0.0
    floor_id = matched[0][0]["floor_id"]
    for ap, rssi in matched:
        if rssi is None:
            continue
        w = 1.0 / max(1.0, abs(rssi))  # stronger signal (smaller |rssi|) -> bigger weight
        wx += ap["x"] * w
        wy += ap["y"] * w
        total_w += w
    if total_w == 0:
        ap, _ = matched[0]
        return Candidate(
            x=ap["x"], y=ap["y"], floor_id=ap["floor_id"],
            accuracy_m=ap.get("coverage_radius_m", 8.0), confidence=0.55,
            source="wifi_single",
        )
    x, y = wx / total_w, wy / total_w
    # More corroborating APs -> tighter accuracy claim, still bounded.
    accuracy_m = max(3.0, 10.0 - len(matched))
    confidence = min(0.85, 0.5 + 0.1 * len(matched))
    return Candidate(
        x=x, y=y, floor_id=floor_id, accuracy_m=accuracy_m,
        confidence=confidence, source="wifi_trilateration",
    )


def gps_to_floor_local(
    *, lat: float, lng: float, origin_lat: float, origin_lng: float,
    rotation_deg: float, meters_per_unit: float,
) -> Tuple[float, float]:
    """Equirectangular approximation - fine at building scale (<< 1km)."""
    R = 6371000.0
    dlat = math.radians(lat - origin_lat)
    dlng = math.radians(lng - origin_lng)
    mean_lat = math.radians((lat + origin_lat) / 2.0)
    north_m = dlat * R
    east_m = dlng * R * math.cos(mean_lat)

    theta = math.radians(rotation_deg)
    x = (east_m * math.cos(theta) - north_m * math.sin(theta)) / meters_per_unit
    y = (east_m * math.sin(theta) + north_m * math.cos(theta)) / meters_per_unit
    return x, y


def gps_candidate(
    *, lat: float, lng: float, gps_accuracy_m: float, floor_id: int,
    origin_lat: Optional[float], origin_lng: Optional[float],
    geo_rotation_deg: Optional[float], meters_per_unit: Optional[float],
) -> Optional[Candidate]:
    if origin_lat is None or origin_lng is None or meters_per_unit is None:
        return None  # floor has no GPS calibration - GPS unusable here
    x, y = gps_to_floor_local(
        lat=lat, lng=lng, origin_lat=origin_lat, origin_lng=origin_lng,
        rotation_deg=geo_rotation_deg or 0.0, meters_per_unit=meters_per_unit,
    )
    # Never let GPS alone claim high confidence - it's known-unreliable indoors.
    confidence = min(GPS_MAX_CONFIDENCE, 8.0 / max(gps_accuracy_m, 8.0))
    return Candidate(
        x=x, y=y, floor_id=floor_id, accuracy_m=max(gps_accuracy_m, 5.0),
        confidence=confidence, source="gps",
    )


def fuse(candidates: Sequence[Candidate]) -> Optional[FusedPosition]:
    candidates = [c for c in candidates if c is not None]
    if not candidates:
        return None
    if len(candidates) == 1:
        c = candidates[0]
        return FusedPosition(
            x=c.x, y=c.y, floor_id=c.floor_id, accuracy_m=c.accuracy_m,
            confidence=c.confidence, source=c.source,
        )

    # Floor = whichever candidate is most confident.
    best = max(candidates, key=lambda c: c.confidence)
    same_floor = [c for c in candidates if c.floor_id == best.floor_id]

    def dist(a: Candidate, b: Candidate) -> float:
        return math.hypot(a.x - b.x, a.y - b.y)

    disagree = any(dist(best, c) > DISAGREEMENT_THRESHOLD_M for c in same_floor)
    if disagree:
        # Signals disagree by a lot - trust the strongest one alone, but
        # don't pretend we're confident about it.
        return FusedPosition(
            x=best.x, y=best.y, floor_id=best.floor_id,
            accuracy_m=best.accuracy_m, confidence=best.confidence * 0.6,
            source=best.source,
        )

    total_w = 0.0
    wx = wy = 0.0
    total_conf = 0.0
    sources = []
    for c in same_floor:
        weight = c.confidence / max(c.accuracy_m, 0.5) ** 2
        wx += c.x * weight
        wy += c.y * weight
        total_w += weight
        total_conf += c.confidence
        sources.append(c.source)

    x, y = wx / total_w, wy / total_w
    accuracy_m = min(c.accuracy_m for c in same_floor)
    confidence = min(0.98, total_conf / len(same_floor) + 0.05 * (len(same_floor) - 1))
    return FusedPosition(
        x=x, y=y, floor_id=best.floor_id, accuracy_m=accuracy_m,
        confidence=confidence, source="+".join(sources),
    )


# ── Map matching ──────────────────────────────────────────────────────────

def _point_in_polygon(x: float, y: float, polygon: Sequence[Tuple[float, float]]) -> bool:
    inside = False
    n = len(polygon)
    j = n - 1
    for i in range(n):
        xi, yi = polygon[i]
        xj, yj = polygon[j]
        if ((yi > y) != (yj > y)) and (
            x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-9) + xi
        ):
            inside = not inside
        j = i
    return inside


def _closest_point_on_segment(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    if dx == 0 and dy == 0:
        return ax, ay
    t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
    t = max(0.0, min(1.0, t))
    return ax + t * dx, ay + t * dy


def snap_to_nearest_room(
    x: float, y: float, rooms: Sequence[dict]
) -> Tuple[float, float, Optional[str]]:
    """
    rooms: [{"name": str, "polygon": [(x,y), ...]}]. If (x,y) already falls
    inside a room, return it unchanged with that room's name. Otherwise snap
    to the nearest room-boundary point so a marker never renders in a wall
    gap / undefined space between rooms.
    """
    if not rooms:
        return x, y, None

    for room in rooms:
        poly = room["polygon"]
        if len(poly) >= 3 and _point_in_polygon(x, y, poly):
            return x, y, room["name"]

    best_dist = None
    best_point = (x, y)
    best_name = None
    for room in rooms:
        poly = room["polygon"]
        n = len(poly)
        if n < 2:
            continue
        for i in range(n):
            ax, ay = poly[i]
            bx, by = poly[(i + 1) % n]
            cx, cy = _closest_point_on_segment(x, y, ax, ay, bx, by)
            d = math.hypot(cx - x, cy - y)
            if best_dist is None or d < best_dist:
                best_dist = d
                best_point = (cx, cy)
                best_name = room["name"]
    return best_point[0], best_point[1], best_name


# ── Smoothing ─────────────────────────────────────────────────────────────

SMOOTHING_ALPHA = 0.4  # lower = smoother/slower, higher = more responsive


def smooth(
    new_x: float, new_y: float,
    prev_x: Optional[float], prev_y: Optional[float],
    alpha: float = SMOOTHING_ALPHA,
) -> Tuple[float, float]:
    """Exponential moving average against the last broadcast point, to kill
    RSSI/GPS jitter before the marker moves on the admin's screen."""
    if prev_x is None or prev_y is None:
        return new_x, new_y
    return (
        alpha * new_x + (1 - alpha) * prev_x,
        alpha * new_y + (1 - alpha) * prev_y,
    )
