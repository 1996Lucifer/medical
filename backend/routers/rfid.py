"""
RFID badge enroll/verify endpoints for the physical ESP32+RC522 devices
built at /Users/dj/Projects/kram/rfid-firmware.

Security model (see that firmware's README for the full design): a card
only ever stores an AES-256-GCM-encrypted opaque 128-bit token. The
writer device generates that token and hands it to us once, at enrollment
time, so we can map it to a staff member; the reader device decrypts it
locally on every tap and hands it back to us for a yes/no access decision.
The token itself is meaningless without the mapping we hold here, and we
never store it in the clear — only its SHA-256 hash (see `_hash_token`).

Auth is a THIRD kind, distinct from the `get_current_user` JWT dependency
used everywhere else and from the public/unauthenticated routers: a device
authenticates with a static `Authorization: Bearer <device_key>` header
(see `get_current_device`), not a user JWT — because these two endpoints
are called by hardware devices with no notion of a logged-in user.
"""

import datetime
import hashlib
import json
import os
import secrets
from typing import Optional

from fastapi import APIRouter, Depends, Header, HTTPException, status
from pydantic import BaseModel, ConfigDict
from sqlalchemy.orm import Session
from starlette.responses import Response

from camera.attendance_service import mark_attendance_for_staff
from database import get_db
import models
from routers.auth import get_current_user, require_permission

router = APIRouter(prefix="/api/rfid", tags=["rfid"])

ENROLL_SESSION_TTL_SEC = 90


def _hash_token(raw: str) -> str:
    """Same hashing scheme used for both device keys and card tokens —
    a plain SHA-256 hex digest. Neither the raw device key nor the raw
    card token is ever persisted; only this hash is."""
    return hashlib.sha256(raw.encode()).hexdigest()


def _now() -> datetime.datetime:
    return datetime.datetime.now(tz=datetime.timezone.utc)


def ensure_fixed_station(db: "Session") -> None:
    """
    Provisions the one fixed admin-desk RFID station from a pre-shared key
    in `RFID_STATION_DEVICE_KEY`, instead of the old flow (mint a random key
    via POST /devices, show it once in the app, flash it into the device
    right then). That flow made provisioning happen as a side effect of
    whatever admin action first needed a device to exist - fragile, and it
    surfaced a raw crypto key inside routine staff-enrollment UI.

    Here the key is decided once, out of band (put it in .env AND flash the
    exact same value into the device's firmware/setup portal), and this
    just makes sure a matching `RfidDevice` row exists - called on every
    startup, so it's a no-op once the row is already there. Safe to call
    with the env var unset (no-op) for deployments still using dynamic
    per-device registration via the API.
    """
    raw_key = os.getenv("RFID_STATION_DEVICE_KEY")
    if not raw_key:
        return
    key_hash = _hash_token(raw_key)
    existing = (
        db.query(models.RfidDevice)
        .filter(models.RfidDevice.device_key_hash == key_hash)
        .first()
    )
    if existing:
        if not existing.is_active:
            existing.is_active = True
            db.commit()
        return
    db.add(
        models.RfidDevice(
            label="Admin Desk Enrollment Station",
            device_key_hash=key_hash,
            is_active=True,
        )
    )
    db.commit()


def _as_utc(dt: Optional[datetime.datetime]) -> Optional[datetime.datetime]:
    if dt is None:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=datetime.timezone.utc)
    return dt.astimezone(datetime.timezone.utc)


def get_current_device(
    authorization: Optional[str] = Header(None),
    db: Session = Depends(get_db),
) -> models.RfidDevice:
    """
    Device-bearer counterpart to `routers.auth.get_current_user`. Hash-
    compares the `Authorization: Bearer <key>` header against
    `RfidDevice.device_key_hash` instead of decoding a JWT — devices are
    provisioned once (see POST /api/rfid/devices) and never log in.
    """
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate device credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if not authorization or not authorization.lower().startswith("bearer "):
        raise credentials_exception

    raw_key = authorization[len("Bearer "):].strip()
    if not raw_key:
        raise credentials_exception

    key_hash = _hash_token(raw_key)
    device = (
        db.query(models.RfidDevice)
        .filter(models.RfidDevice.device_key_hash == key_hash)
        .first()
    )
    if not device or not device.is_active:
        raise credentials_exception

    device.last_seen_at = _now()
    db.commit()
    return device


class CheckInRequest(BaseModel):
    ip_address: str


@router.post("/checkin")
def device_checkin(
    body: CheckInRequest,
    db: Session = Depends(get_db),
    device: models.RfidDevice = Depends(get_current_device),
):
    """
    Called by the device itself right after it connects to WiFi (see
    rfid-firmware's main_writer.cpp/main_reader.cpp) so the backend always
    knows its current LAN IP - no Serial Monitor, no hand-typed .env entry,
    and no manual re-entry when a DHCP lease later hands it a different
    address. This is what POST /station/reset-config below reads from,
    instead of a fixed env var.
    """
    device.ip_address = body.ip_address
    db.commit()
    return {"ok": True}


# ── Admin: device registration ──────────────────────────────────────────────


class RegisterDeviceRequest(BaseModel):
    label: str


class RegisterDeviceResponse(BaseModel):
    device_id: int
    label: str
    device_key: str


@router.post("/devices", response_model=RegisterDeviceResponse)
def register_device(
    body: RegisterDeviceRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_permission("manage_devices")),
):
    """
    Provision a new physical RFID device (writer or reader). Returns the
    raw bearer key exactly once — only its hash is stored, so if it's lost
    the only recovery is registering a replacement device.
    """
    raw_key = secrets.token_hex(24)
    device = models.RfidDevice(
        label=body.label,
        device_key_hash=_hash_token(raw_key),
        is_active=True,
    )
    db.add(device)
    db.commit()
    db.refresh(device)
    return RegisterDeviceResponse(
        device_id=device.id, label=device.label, device_key=raw_key
    )


class DeviceListItem(BaseModel):
    id: int
    label: str
    is_active: bool
    last_seen_at: Optional[datetime.datetime]
    created_at: Optional[datetime.datetime]
    model_config = ConfigDict(from_attributes=True)


@router.get("/devices", response_model=list[DeviceListItem])
def list_devices(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_permission("manage_devices")),
):
    return (
        db.query(models.RfidDevice)
        .order_by(models.RfidDevice.created_at.desc())
        .all()
    )


class ResetStationConfigResponse(BaseModel):
    ok: bool
    detail: str


@router.post("/station/reset-config", response_model=ResetStationConfigResponse)
def reset_station_config(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_permission("manage_devices")),
):
    """
    Remotely triggers the fixed admin-desk station's own `POST
    /reset-config` (see rfid-firmware's DeviceSetup.h/.cpp) - clears its
    saved WiFi/backend config and restarts it into the setup portal,
    without needing physical access to its BOOT button.

    This calls OUT to the device over the LAN using the device's own
    self-reported IP (see device_checkin - never a hand-typed .env entry)
    and RFID_STATION_DEVICE_KEY from `.env` (see ensure_fixed_station) -
    the raw key never passes through the Flutter app or an HTTP response;
    the app only ever calls this endpoint, authenticated with its own admin
    JWT.
    """
    import requests

    device_key = os.getenv("RFID_STATION_DEVICE_KEY")
    if not device_key:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="RFID_STATION_DEVICE_KEY not configured in .env",
        )
    device = (
        db.query(models.RfidDevice)
        .filter(models.RfidDevice.device_key_hash == _hash_token(device_key))
        .first()
    )
    if not device or not device.ip_address:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "Station hasn't checked in yet, so its IP isn't known. "
                "Make sure it's powered on and connected to WiFi - it "
                "reports its IP automatically once it does."
            ),
        )
    device_ip = device.ip_address
    try:
        resp = requests.post(
            f"http://{device_ip}/reset-config",
            headers={"Authorization": f"Bearer {device_key}"},
            timeout=5,
        )
    except requests.RequestException as e:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Could not reach the station at {device_ip}: {e}",
        )
    if resp.status_code != 200:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Station rejected the reset request: HTTP {resp.status_code}",
        )
    return ResetStationConfigResponse(
        ok=True, detail="Station is restarting into its setup portal."
    )


# ── Admin: enroll sessions ───────────────────────────────────────────────────


class CreateEnrollSessionRequest(BaseModel):
    device_id: int
    staff_id: int


class CreateEnrollSessionResponse(BaseModel):
    session_id: int
    expires_at: datetime.datetime


@router.post("/enroll-sessions", response_model=CreateEnrollSessionResponse)
def create_enroll_session(
    body: CreateEnrollSessionRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_permission("manage_devices")),
):
    """
    Open a short-lived (90s) window binding the next card tapped on
    `device_id` to `staff_id`. The Flutter enroll flow calls this right
    before asking the admin to tap a blank card on the writer device, then
    polls GET /enroll-sessions/{id} for completion.
    """
    device = db.query(models.RfidDevice).filter(models.RfidDevice.id == body.device_id).first()
    if not device or not device.is_active:
        raise HTTPException(status_code=404, detail="Device not found or inactive")

    staff = db.query(models.Staff).filter(models.Staff.id == body.staff_id).first()
    if not staff:
        raise HTTPException(status_code=404, detail="Staff not found")

    session = models.RfidEnrollSession(
        device_id=body.device_id,
        staff_id=body.staff_id,
        expires_at=_now() + datetime.timedelta(seconds=ENROLL_SESSION_TTL_SEC),
    )
    db.add(session)
    db.commit()
    db.refresh(session)
    return CreateEnrollSessionResponse(
        session_id=session.id, expires_at=session.expires_at
    )


class EnrollSessionStatusResponse(BaseModel):
    consumed: bool
    expired: bool


@router.get("/enroll-sessions/{session_id}", response_model=EnrollSessionStatusResponse)
def get_enroll_session_status(
    session_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(require_permission("manage_devices")),
):
    session = (
        db.query(models.RfidEnrollSession)
        .filter(models.RfidEnrollSession.id == session_id)
        .first()
    )
    if not session:
        raise HTTPException(status_code=404, detail="Enroll session not found")

    return EnrollSessionStatusResponse(
        consumed=session.consumed_at is not None,
        expired=session.consumed_at is None and _as_utc(session.expires_at) < _now(),
    )


# ── Device-facing: enroll + verify ──────────────────────────────────────────


class TokenBody(BaseModel):
    token: str


@router.post("/enroll")
def enroll_card(
    body: TokenBody,
    db: Session = Depends(get_db),
    device: models.RfidDevice = Depends(get_current_device),
):
    """
    Called by a writer device right after it encrypts a fresh token onto a
    blank card. Binds that token to whichever staff member has the most
    recent still-open enroll session for this device.
    """
    session = (
        db.query(models.RfidEnrollSession)
        .filter(models.RfidEnrollSession.device_id == device.id)
        .filter(models.RfidEnrollSession.consumed_at.is_(None))
        .filter(models.RfidEnrollSession.expires_at > _now())
        .order_by(models.RfidEnrollSession.created_at.desc())
        .first()
    )
    if not session:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="No pending enroll session for this device",
        )

    # One active card per person — revoke any prior card before issuing
    # the new one.
    existing = (
        db.query(models.RfidCard)
        .filter(models.RfidCard.staff_id == session.staff_id)
        .filter(models.RfidCard.revoked_at.is_(None))
        .first()
    )
    now = _now()
    if existing:
        existing.revoked_at = now
        db.add(existing)

    card = models.RfidCard(
        staff_id=session.staff_id,
        token_hash=_hash_token(body.token),
        issued_at=now,
    )
    db.add(card)

    session.consumed_at = now
    db.add(session)

    db.commit()
    return {"success": True}


@router.post("/verify")
def verify_card(
    body: TokenBody,
    db: Session = Depends(get_db),
    device: models.RfidDevice = Depends(get_current_device),
):
    """
    Called by a reader device on every tap. The firmware does a crude
    substring check for the literal `"granted":true` in the response body,
    so the response is hand-serialized with `separators=(",", ":")` to
    guarantee there's no space after the colon (FastAPI's default JSON
    encoder inserts one — `{"granted": true, ...}` — which would NOT match).
    """
    token_hash = _hash_token(body.token)
    card = (
        db.query(models.RfidCard)
        .filter(models.RfidCard.token_hash == token_hash)
        .filter(models.RfidCard.revoked_at.is_(None))
        .first()
    )

    if not card:
        payload = {"granted": False}
    else:
        result = mark_attendance_for_staff(
            db, staff_id=card.staff_id, source="rfid"
        )
        if not result:
            # Card exists but its staff row is gone (e.g. staff deleted
            # without revoking the card) — deny rather than 500.
            payload = {"granted": False}
        else:
            payload = {
                "granted": True,
                "staff_name": result["staff_name"],
                "role": result["role"],
            }

    return Response(
        content=json.dumps(payload, separators=(",", ":")),
        media_type="application/json",
    )
