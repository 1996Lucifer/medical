import datetime
import logging
import threading
from typing import Dict, FrozenSet, List, Optional

from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, ConfigDict
from sqlalchemy.orm import Session

from database import SessionLocal, get_db
import models
from routers.auth import get_current_user
from services.calls.authorization import can_call
from services.calls.naming import display_name
from services.ws_auth import authenticate_websocket

router = APIRouter(tags=["calls"])
logger = logging.getLogger("calls")

# user_id -> connected WebSocket. Presence + relay only - no call state is
# held here; the client (CallService, Flutter side) owns call state, this
# is purely a message router, same design as kram's signaling relay.
_CONNECTIONS: Dict[int, WebSocket] = {}
_LOCK = threading.Lock()

# {caller_id, callee_id} -> the CallLog row id for their current
# not-yet-resolved call attempt, so the accept/reject/hangup that arrives
# later (identified only by from/to user ids, same as everything else on
# this relay) can be matched back to the row the invite created. Cleared
# the moment the call reaches a terminal status. Same in-process, in-memory
# lifetime as _CONNECTIONS above - a lost row here just means a call never
# gets its outcome recorded past "ringing", it never breaks the relay.
_PENDING_CALL_LOG: Dict[FrozenSet[int], int] = {}
_PENDING_LOCK = threading.Lock()


def _log_call_start(caller_id: int, callee_id: int, mode: str, status: str) -> None:
    db = SessionLocal()
    try:
        row = models.CallLog(
            caller_id=caller_id, callee_id=callee_id, mode=mode, status=status
        )
        db.add(row)
        db.commit()
        db.refresh(row)
        if status == "ringing":
            with _PENDING_LOCK:
                _PENDING_CALL_LOG[frozenset((caller_id, callee_id))] = row.id
    finally:
        db.close()


def _log_call_resolve(caller_id: int, callee_id: int, status: str) -> None:
    with _PENDING_LOCK:
        log_id = _PENDING_CALL_LOG.pop(frozenset((caller_id, callee_id)), None)
    if log_id is None:
        return
    db = SessionLocal()
    try:
        row = db.query(models.CallLog).filter(models.CallLog.id == log_id).first()
        if row is None:
            return
        # A hangup after the call was already answered is just "call ended
        # normally" - keep the "answered" status, only stamp when it ended.
        if row.status == "ringing":
            row.status = status
        row.ended_at = datetime.datetime.utcnow()
        db.commit()
    finally:
        db.close()


def get_connection(user_id: int) -> Optional[WebSocket]:
    """Used by routers/messages.py to push a live envelope to a connected
    user over the same signaling socket, without duplicating the
    presence-tracking dict here."""
    with _LOCK:
        return _CONNECTIONS.get(user_id)


@router.websocket("/ws/calls")
async def call_signaling(websocket: WebSocket):
    # Auth token travels as the first WS message, not a ?token= query
    # param - see services/ws_auth.py for why. authenticate_websocket
    # already accepts() the connection itself (a message can't be
    # received before accept), so this handler never calls accept()
    # again.
    db = SessionLocal()
    try:
        user = await authenticate_websocket(websocket, db)
    finally:
        db.close()
    if user is None:
        await websocket.close(code=4401)
        return

    with _LOCK:
        existing = _CONNECTIONS.get(user.id)
        _CONNECTIONS[user.id] = websocket
    # A second tab/device logging in as the same user replaces the old
    # connection - close the stale one rather than silently leaving two
    # sockets registered under one id (mirrors kram's dedup behavior).
    if existing is not None and existing is not websocket:
        try:
            await existing.close()
        except Exception:
            logger.debug("Failed to close stale connection for user %s", user.id, exc_info=True)

    try:
        while True:
            envelope = await websocket.receive_json()
            msg_type = envelope.get("type")
            to_user_id = envelope.get("to")

            # Chat messages no longer travel over this socket at all - see
            # routers/messages.py, which persists them (this relay dropped
            # anything sent to an offline recipient on the floor with no
            # trace) and pushes live delivery via get_connection() above.
            # Only call-invite still needs the can_call() authorization gate
            # here.
            if msg_type == "call" and envelope.get("action") == "invite":
                db = SessionLocal()
                try:
                    # `user` was loaded (and its session closed) back in
                    # _authenticate_ws_token at connect time - re-fetch it in
                    # this fresh session so can_call's relationship lookups
                    # (patient_profile, etc.) don't hit a DetachedInstanceError.
                    live_user = db.query(models.User).filter(models.User.id == user.id).first()
                    allowed = live_user is not None and can_call(db, live_user, to_user_id)
                finally:
                    db.close()
                if not allowed:
                    await websocket.send_json({
                        "type": msg_type,
                        "action": "denied",
                        "from": user.id,
                        "reason": "You are not permitted to contact this person.",
                    })
                    continue

            if not isinstance(to_user_id, int):
                continue

            envelope["from"] = user.id
            with _LOCK:
                target = _CONNECTIONS.get(to_user_id)

            if msg_type == "call":
                action = envelope.get("action")
                if action == "invite":
                    _log_call_start(
                        caller_id=user.id,
                        callee_id=to_user_id,
                        mode=envelope.get("mode") or "audio",
                        status="ringing" if target is not None else "unavailable",
                    )
                elif action == "accept":
                    _log_call_resolve(user.id, to_user_id, status="answered")
                elif action == "reject":
                    _log_call_resolve(user.id, to_user_id, status="declined")
                elif action == "hangup":
                    _log_call_resolve(user.id, to_user_id, status="missed")

            if target is None:
                if msg_type == "call":
                    await websocket.send_json({
                        "type": "call",
                        "action": "unavailable",
                        "from": to_user_id,
                    })
                continue

            try:
                await target.send_json(envelope)
            except Exception:
                logger.warning(
                    "Failed to relay %s message from user %s to user %s",
                    msg_type, user.id, to_user_id, exc_info=True,
                )

    except WebSocketDisconnect:
        pass
    finally:
        with _LOCK:
            if _CONNECTIONS.get(user.id) is websocket:
                del _CONNECTIONS[user.id]


class CallLogEntry(BaseModel):
    id: int
    peer_id: int
    peer_name: str
    direction: str  # "incoming" or "outgoing", relative to the caller
    mode: str
    status: str
    created_at: datetime.datetime
    ended_at: Optional[datetime.datetime]
    model_config = ConfigDict(from_attributes=True)


@router.get("/api/calls/log", response_model=List[CallLogEntry])
def get_call_log(
    limit: int = 50,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """
    Recent call attempts involving the current user, most recent first -
    the calling-feature counterpart to GET /api/messages/conversations.
    Works for a peer who was never in the current user's People Directory
    (e.g. an admin/superadmin with no Staff row) exactly like that endpoint
    does, since it resolves names the same way (services/calls/naming).
    """
    rows = (
        db.query(models.CallLog)
        .filter(
            (models.CallLog.caller_id == current_user.id)
            | (models.CallLog.callee_id == current_user.id)
        )
        .order_by(models.CallLog.created_at.desc())
        .limit(min(limit, 100))
        .all()
    )
    entries = []
    for row in rows:
        is_caller = row.caller_id == current_user.id
        peer = row.callee if is_caller else row.caller
        entries.append(
            CallLogEntry(
                id=row.id,
                peer_id=peer.id,
                peer_name=display_name(db, peer),
                direction="outgoing" if is_caller else "incoming",
                mode=row.mode,
                status=row.status,
                created_at=row.created_at,
                ended_at=row.ended_at,
            )
        )
    return entries
