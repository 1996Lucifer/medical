import logging
import threading
from typing import Dict, Optional

import jwt
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from sqlalchemy.orm import Session

from database import SessionLocal
import models
from routers.auth import SECRET_KEY, ALGORITHM
from services.calls.authorization import can_call

router = APIRouter(tags=["calls"])
logger = logging.getLogger("calls")

# user_id -> connected WebSocket. Presence + relay only - no call state is
# held here; the client (CallService, Flutter side) owns call state, this
# is purely a message router, same design as kram's signaling relay.
_CONNECTIONS: Dict[int, WebSocket] = {}
_LOCK = threading.Lock()


def _authenticate_ws_token(token: str) -> Optional[models.User]:
    """
    A WebSocket handshake can't carry a normal Authorization header from a
    browser/Flutter WebSocketChannel, so the JWT is passed as a query param
    instead and validated the same way routers.auth.get_current_user does.
    """
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username = payload.get("sub")
        if username is None:
            return None
    except jwt.PyJWTError:
        return None

    db = SessionLocal()
    try:
        return db.query(models.User).filter(models.User.username == username).first()
    finally:
        db.close()


@router.websocket("/ws/calls")
async def call_signaling(websocket: WebSocket, token: str = Query(...)):
    user = _authenticate_ws_token(token)
    if user is None:
        await websocket.close(code=4401)
        return

    await websocket.accept()

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
                        "type": "call",
                        "action": "denied",
                        "from": user.id,
                        "reason": "You are not permitted to call this person.",
                    })
                    continue

            if not isinstance(to_user_id, int):
                continue

            envelope["from"] = user.id
            with _LOCK:
                target = _CONNECTIONS.get(to_user_id)

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
