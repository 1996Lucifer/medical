"""
Small in-memory caches for indoor-tracking's hottest read paths.

Room polygons and camera positions are static admin-configured data that
almost never changes at runtime, but were being re-queried from the DB on
every single position update: once per ~20s per actively-tracked mobile
client (routers/indoor_tracking.py's /signal) and once per ~30s per
actively-tracked camera-seen session (camera/attendance_service.py's
_feed_camera_seen_signal). At a few dozen concurrent active sessions that's
a steady stream of redundant identical queries. A short TTL plus explicit
invalidation on the admin writes that actually change this data removes
nearly all of it without risking stale data past a few seconds.
"""
import json
import time
from typing import Optional

import models

_ROOM_CACHE_TTL_SEC = 30.0
_room_cache: dict[int, tuple[float, list]] = {}

_CAMERA_CACHE_TTL_SEC = 30.0
# Cache plain (floor_id, x, y, coverage_radius_m) tuples, not the ORM object
# itself - the fetching request's db session is closed well before the TTL
# expires, and caching a detached instance is a DetachedInstanceError
# footgun for any future caller that touches a lazy-loaded attribute.
_camera_cache: dict[int, tuple[float, Optional[tuple]]] = {}


def get_room_dicts_cached(db, floor_id: int) -> list:
    """[{"name": str, "polygon": [(x, y), ...]}] for fusion.snap_to_nearest_room."""
    now = time.monotonic()
    cached = _room_cache.get(floor_id)
    if cached is not None and now - cached[0] < _ROOM_CACHE_TTL_SEC:
        return cached[1]

    rooms = db.query(models.Room).filter(models.Room.floor_id == floor_id).all()
    room_dicts = [
        {"name": r.name, "polygon": [(p["x"], p["y"]) for p in json.loads(r.polygon)]}
        for r in rooms
    ]
    _room_cache[floor_id] = (now, room_dicts)
    return room_dicts


def invalidate_rooms(floor_id: int) -> None:
    _room_cache.pop(floor_id, None)


def get_camera_position_cached(db, camera_id: int) -> Optional[tuple]:
    """(floor_id, x, y, coverage_radius_m), or None if the camera doesn't
    exist or isn't placed on a floor yet."""
    now = time.monotonic()
    cached = _camera_cache.get(camera_id)
    if cached is not None and now - cached[0] < _CAMERA_CACHE_TTL_SEC:
        return cached[1]

    camera = db.query(models.Camera).filter(models.Camera.id == camera_id).first()
    if camera is None or camera.floor_id is None or camera.x is None or camera.y is None:
        result = None
    else:
        result = (camera.floor_id, camera.x, camera.y, camera.coverage_radius_m)
    _camera_cache[camera_id] = (now, result)
    return result


def invalidate_camera(camera_id: int) -> None:
    _camera_cache.pop(camera_id, None)
