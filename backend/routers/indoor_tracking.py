"""
Indoor location tracking: staff-facing signal ingestion, Super Admin live
snapshot + WebSocket feed, and floor/room/Wi-Fi-AP/geofence admin config.

Mounted WITHOUT the app-wide `auth_dep` (like security.router/events.router/
calls.router) because it carries a `@router.websocket` route, and FastAPI's
router-level `dependencies=` doesn't apply to websocket handlers - auth is
applied per-HTTP-route here instead (see main.py's note on this).
"""
import datetime
import json
import os
import shutil
import uuid
from typing import List, Optional

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, ConfigDict
from sqlalchemy.orm import Session

from database import get_db
import models
from camera.attendance_service import checkout_session, mark_attendance_for_staff
from indoor_tracking import fusion, gating
from indoor_tracking.floor_cache import get_room_dicts_cached, invalidate_camera, invalidate_rooms
from indoor_tracking.hub import hub
from routers.auth import get_current_user, require_permission
from routers.site_config import _get_or_create_config
from services.ws_auth import authenticate_websocket

router = APIRouter(prefix="/api/indoor-tracking", tags=["indoor-tracking"])


# ── Schemas ────────────────────────────────────────────────────────────────

class WifiReading(BaseModel):
    bssid: str
    rssi: Optional[float] = None


class WifiSignal(BaseModel):
    bssid: str
    ssid: Optional[str] = None
    scan: Optional[List[WifiReading]] = None


class GpsSignal(BaseModel):
    lat: float
    lng: float
    accuracy_m: float


class SignalRequest(BaseModel):
    # No attendance_session_id: the session is resolved (and, if presence is
    # detected with none open yet, created) server-side from the
    # authenticated user - the app itself is a valid check-in channel now,
    # not only something that reports into a session opened elsewhere.
    wifi: Optional[WifiSignal] = None
    gps: Optional[GpsSignal] = None


class RoomIn(BaseModel):
    name: str
    room_type: str = "room"
    polygon: List[dict]  # [{"x":..,"y":..}, ...]
    is_restricted: bool = False


class FloorIn(BaseModel):
    building_id: int
    name: str
    level: int = 0
    width_m: float
    height_m: float
    floorplan_image_path: Optional[str] = None
    origin_lat: Optional[float] = None
    origin_lng: Optional[float] = None
    geo_rotation_deg: Optional[float] = None
    meters_per_unit: Optional[float] = None


class WifiApIn(BaseModel):
    floor_id: int
    bssid: str
    ssid: Optional[str] = None
    x: float
    y: float
    tx_power_dbm: Optional[float] = None
    coverage_radius_m: float = 8.0


class GeofenceIn(BaseModel):
    geofence_polygon: List[dict]  # [{"lat":..,"lng":..}, ...]
    working_hours_start: Optional[str] = None  # "HH:MM"
    working_hours_end: Optional[str] = None


# ── Staff-facing: signal ingestion ─────────────────────────────────────────

def _resolve_staff_for_user(db: Session, user: models.User) -> Optional[models.Staff]:
    return db.query(models.Staff).filter(models.Staff.user_id == user.id).first()


def _open_session_for_staff(db: Session, staff_id: int) -> Optional[models.Attendance]:
    return (
        db.query(models.Attendance)
        .filter(models.Attendance.staff_id == staff_id, models.Attendance.exit_time.is_(None))
        .order_by(models.Attendance.entry_time.desc())
        .first()
    )


@router.post("/signal")
def post_signal(
    body: SignalRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    staff = _resolve_staff_for_user(db, current_user)
    if staff is None:
        raise HTTPException(status_code=403, detail="This account has no linked staff record")

    hospital = db.query(models.SiteConfig).first()
    now = datetime.datetime.now(tz=datetime.timezone.utc)
    # working_hours_start/end are entered as local wall-clock time, not UTC
    # - compare against local server time. (Single-timezone assumption,
    # same as the rest of this app, e.g. Attendance.date's local
    # `date.today()`.)
    now_local = datetime.datetime.now()

    geofence_polygon = None
    if hospital and hospital.geofence_polygon:
        pts = json.loads(hospital.geofence_polygon)
        geofence_polygon = [(p["lat"], p["lng"]) for p in pts]

    matched_ap = None
    if body.wifi:
        matched_ap = (
            db.query(models.WifiAccessPoint)
            .filter(models.WifiAccessPoint.bssid == body.wifi.bssid)
            .first()
        )

    record = _open_session_for_staff(db, staff.id)

    if record is None:
        # No open session yet - the app itself is a valid check-in channel:
        # a known hospital Wi-Fi AP, or GPS inside the geofence, is enough
        # evidence of presence to open one, same as a face/RFID detection
        # would. Reuses the exact shared session logic those channels go
        # through (camera/attendance_service.py) rather than a parallel
        # implementation.
        present = matched_ap is not None or (
            body.gps and geofence_polygon
            and gating.point_in_geo_polygon(body.gps.lat, body.gps.lng, geofence_polygon)
        )
        if not present:
            return {"status": "not_at_hospital"}
        mark_attendance_for_staff(db, staff_id=staff.id, source="app")
        record = _open_session_for_staff(db, staff.id)
        if record is None:
            return {"status": "not_at_hospital"}

    if not hub.is_active(record.id):
        raise HTTPException(status_code=400, detail="Tracking is not active for this session")

    if record.exit_time is not None:
        hub.stop_session(record.id)
        raise HTTPException(status_code=400, detail="Attendance session has ended")

    # Working-hours source priority: the checked-in staff member's own
    # shift first (the hospital runs 24x7 - there's no single hospital-wide
    # window that's actually true), falling back to the hospital-wide
    # SiteConfig fields only if this staff member has no shift configured,
    # falling back to "no time-based gating" if neither is set.
    if staff.shift_start and staff.shift_end:
        working_hours_start, working_hours_end = staff.shift_start, staff.shift_end
    else:
        working_hours_start = hospital.working_hours_start if hospital else None
        working_hours_end = hospital.working_hours_end if hospital else None

    state = hub.get_session(record.id)
    status = gating.decide_status(
        attendance_session_open=True,
        gps={"lat": body.gps.lat, "lng": body.gps.lng} if body.gps else None,
        matched_known_wifi_ap=matched_ap is not None,
        geofence_polygon=geofence_polygon,
        now=now_local,
        working_hours_start=working_hours_start,
        working_hours_end=working_hours_end,
        previous_status=state.status if state else "active",
    )

    if status == "stopped":
        # Outside the geofence AND outside shift hours (or the session was
        # already closed some other way) - this is a real end of duty, not
        # a temporary step-out, so perform an actual DB checkout rather
        # than only dropping the in-memory tracking state.
        checkout_session(db, record, now, reason="left_geofence_after_shift")
        db.commit()
        return {"status": "stopped"}

    if status != "active":
        hub.set_status(record.id, status)
        return {"status": status}

    candidates = []

    if body.wifi:
        floor_id_hint = matched_ap.floor_id if matched_ap else None
        aps_q = db.query(models.WifiAccessPoint)
        if floor_id_hint is not None:
            aps_q = aps_q.filter(models.WifiAccessPoint.floor_id == floor_id_hint)
        known_aps = [
            {
                "bssid": ap.bssid, "x": ap.x, "y": ap.y, "floor_id": ap.floor_id,
                "coverage_radius_m": ap.coverage_radius_m, "tx_power_dbm": ap.tx_power_dbm,
            }
            for ap in aps_q.all()
        ]
        readings = [{"bssid": body.wifi.bssid, "rssi": None}]
        if body.wifi.scan:
            readings = [{"bssid": r.bssid, "rssi": r.rssi} for r in body.wifi.scan]
        candidates.append(fusion.wifi_candidate(known_aps=known_aps, readings=readings))

    if body.gps and matched_ap is not None:
        floor = db.query(models.Floor).filter(models.Floor.id == matched_ap.floor_id).first()
        if floor is not None:
            candidates.append(
                fusion.gps_candidate(
                    lat=body.gps.lat, lng=body.gps.lng, gps_accuracy_m=body.gps.accuracy_m,
                    floor_id=floor.id, origin_lat=floor.origin_lat, origin_lng=floor.origin_lng,
                    geo_rotation_deg=floor.geo_rotation_deg, meters_per_unit=floor.meters_per_unit,
                )
            )

    fused = fusion.fuse(candidates)
    if fused is None:
        # No usable signal this update - hold last known position/state
        # rather than guessing.
        return {"status": "active", "note": "no usable signal"}

    x, y = fusion.smooth(fused.x, fused.y, state.x if state else None, state.y if state else None)

    room_dicts = get_room_dicts_cached(db, fused.floor_id)
    x, y, area_name = fusion.snap_to_nearest_room(x, y, room_dicts)

    hub.update_position(
        record.id, floor_id=fused.floor_id, x=x, y=y, area_name=area_name,
        accuracy_m=fused.accuracy_m, confidence=fused.confidence, source=fused.source,
        status="active",
    )
    return {"status": "active"}


# ── Super Admin: snapshot + live feed ───────────────────────────────────────

@router.get("/floors/{floor_id}/active")
def get_active_on_floor(
    floor_id: int,
    _admin: models.User = Depends(require_permission("view_indoor_tracking")),
):
    return hub.snapshot(floor_id)


@router.get("/floors")
def list_published_floors(
    db: Session = Depends(get_db),
    _admin: models.User = Depends(require_permission("view_indoor_tracking")),
):
    floors = db.query(models.Floor).filter(models.Floor.published.is_(True)).all()
    return [
        {
            "id": f.id, "building_id": f.building_id, "name": f.name, "level": f.level,
            "width_m": f.width_m, "height_m": f.height_m,
            "floorplan_image_path": f.floorplan_image_path,
        }
        for f in floors
    ]


def _serialize_rooms(db: Session, floor_id: int) -> list:
    rooms = db.query(models.Room).filter(models.Room.floor_id == floor_id).all()
    return [
        {"id": r.id, "name": r.name, "room_type": r.room_type,
         "polygon": json.loads(r.polygon), "is_restricted": r.is_restricted}
        for r in rooms
    ]


@router.get("/floors/{floor_id}/rooms")
def list_floor_rooms(
    floor_id: int,
    db: Session = Depends(get_db),
    _admin: models.User = Depends(require_permission("view_indoor_tracking")),
):
    return _serialize_rooms(db, floor_id)


@router.websocket("/ws")
async def indoor_tracking_ws(websocket: WebSocket, floor_id: int = Query(...)):
    # Auth token travels as the first WS message, not a ?token= query
    # param - see services/ws_auth.py. That's especially important here:
    # this socket streams live staff/patient locations, so a token
    # leaked via a proxy/access log wouldn't just replay a session, it
    # would let someone watch where people physically are.
    from database import SessionLocal
    from routers.auth import has_permission

    db = SessionLocal()
    try:
        user = await authenticate_websocket(websocket, db)
        if user is None or not has_permission(user, "view_indoor_tracking"):
            await websocket.close(code=4403)
            return
    finally:
        db.close()

    hub.connect(websocket, floor_id)
    try:
        for state in hub.snapshot(floor_id):
            await websocket.send_json({"type": "position_update", "data": state})
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        hub.disconnect(websocket, floor_id)
    except Exception:
        hub.disconnect(websocket, floor_id)


# ── Admin: floors / rooms / wifi APs / geofence ─────────────────────────────

admin_router = APIRouter(
    prefix="/api/indoor-tracking/admin",
    tags=["indoor-tracking-admin"],
    dependencies=[Depends(require_permission("manage_indoor_tracking"))],
)


# SiteConfig doubles as the indoor-tracking spatial model's "Hospital" (see
# the docstring on models.SiteConfig) - reuse the one singleton get-or-create
# helper rather than a second copy of the same query/create/commit logic.
_get_or_create_site_config = _get_or_create_config


@admin_router.get("/hospital")
def get_hospital(db: Session = Depends(get_db)):
    hospital = db.query(models.SiteConfig).first()
    if hospital is None:
        return None
    return {
        "id": hospital.id,
        "name": hospital.hospital_name,
        "geofence_polygon": json.loads(hospital.geofence_polygon) if hospital.geofence_polygon else [],
        "working_hours_start": hospital.working_hours_start.isoformat() if hospital.working_hours_start else None,
        "working_hours_end": hospital.working_hours_end.isoformat() if hospital.working_hours_end else None,
    }


@admin_router.put("/hospital/geofence")
def set_geofence(body: GeofenceIn, db: Session = Depends(get_db)):
    hospital = _get_or_create_site_config(db)

    hospital.geofence_polygon = json.dumps(body.geofence_polygon)
    hospital.working_hours_start = (
        datetime.time.fromisoformat(body.working_hours_start) if body.working_hours_start else None
    )
    hospital.working_hours_end = (
        datetime.time.fromisoformat(body.working_hours_end) if body.working_hours_end else None
    )
    db.commit()
    return {"status": "saved"}


@admin_router.post("/buildings")
def create_building(name: str, db: Session = Depends(get_db)):
    hospital = _get_or_create_site_config(db)
    building = models.Building(hospital_id=hospital.id, name=name)
    db.add(building)
    db.commit()
    db.refresh(building)
    return {"id": building.id}


@admin_router.get("/buildings")
def list_buildings(db: Session = Depends(get_db)):
    buildings = db.query(models.Building).all()
    return [{"id": b.id, "hospital_id": b.hospital_id, "name": b.name} for b in buildings]


@admin_router.post("/floors")
def create_floor(body: FloorIn, db: Session = Depends(get_db)):
    floor = models.Floor(**body.model_dump())
    db.add(floor)
    db.commit()
    db.refresh(floor)
    return {"id": floor.id}


@admin_router.get("/floors")
def list_floors(db: Session = Depends(get_db)):
    floors = db.query(models.Floor).all()
    return [
        {
            "id": f.id, "building_id": f.building_id, "name": f.name, "level": f.level,
            "width_m": f.width_m, "height_m": f.height_m,
            "floorplan_image_path": f.floorplan_image_path, "published": f.published,
        }
        for f in floors
    ]


@admin_router.post("/floors/{floor_id}/floorplan-image")
def upload_floorplan_image(floor_id: int, file: UploadFile = File(...), db: Session = Depends(get_db)):
    floor = db.query(models.Floor).filter(models.Floor.id == floor_id).first()
    if floor is None:
        raise HTTPException(status_code=404, detail="Floor not found")

    upload_dir = "uploads/floorplans"
    os.makedirs(upload_dir, exist_ok=True)
    ext = os.path.splitext(file.filename or "")[1] or ".png"
    filename = f"{uuid.uuid4().hex}{ext}"
    with open(os.path.join(upload_dir, filename), "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    floor.floorplan_image_path = f"floorplans/{filename}"
    db.commit()
    return {"floorplan_image_path": floor.floorplan_image_path}


@admin_router.post("/floors/{floor_id}/publish")
def publish_floor(floor_id: int, db: Session = Depends(get_db)):
    floor = db.query(models.Floor).filter(models.Floor.id == floor_id).first()
    if floor is None:
        raise HTTPException(status_code=404, detail="Floor not found")
    floor.published = True
    db.commit()
    return {"status": "published"}


@admin_router.post("/floors/{floor_id}/rooms")
def create_room(floor_id: int, body: RoomIn, db: Session = Depends(get_db)):
    floor = db.query(models.Floor).filter(models.Floor.id == floor_id).first()
    if floor is None:
        raise HTTPException(status_code=404, detail="Floor not found")
    room = models.Room(
        floor_id=floor_id, name=body.name, room_type=body.room_type,
        polygon=json.dumps(body.polygon), is_restricted=body.is_restricted,
    )
    db.add(room)
    db.commit()
    db.refresh(room)
    invalidate_rooms(floor_id)
    return {"id": room.id}


@admin_router.get("/floors/{floor_id}/rooms")
def list_rooms(floor_id: int, db: Session = Depends(get_db)):
    return _serialize_rooms(db, floor_id)


@admin_router.post("/wifi-aps")
def create_wifi_ap(body: WifiApIn, db: Session = Depends(get_db)):
    ap = models.WifiAccessPoint(**body.model_dump())
    db.add(ap)
    db.commit()
    db.refresh(ap)
    return {"id": ap.id}


@admin_router.get("/floors/{floor_id}/wifi-aps")
def list_wifi_aps(floor_id: int, db: Session = Depends(get_db)):
    aps = db.query(models.WifiAccessPoint).filter(models.WifiAccessPoint.floor_id == floor_id).all()
    return [
        {"id": a.id, "bssid": a.bssid, "ssid": a.ssid, "x": a.x, "y": a.y,
         "coverage_radius_m": a.coverage_radius_m}
        for a in aps
    ]


@admin_router.put("/cameras/{camera_id}/position")
def set_camera_position(camera_id: int, floor_id: int, x: float, y: float, db: Session = Depends(get_db)):
    camera = db.query(models.Camera).filter(models.Camera.id == camera_id).first()
    if camera is None:
        raise HTTPException(status_code=404, detail="Camera not found")
    camera.floor_id = floor_id
    camera.x = x
    camera.y = y
    db.commit()
    invalidate_camera(camera_id)
    return {"status": "saved"}
