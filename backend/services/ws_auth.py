import asyncio
from typing import Optional

import jwt
from fastapi import WebSocket
from sqlalchemy.orm import Session

import models
from routers.auth import SECRET_KEY, ALGORITHM

AUTH_TIMEOUT_SECONDS = 5.0


async def authenticate_websocket(websocket: WebSocket, db: Session) -> Optional[models.User]:
    """
    Accepts the connection, then requires the FIRST message to be
    {"type": "auth", "token": "<jwt>"} within AUTH_TIMEOUT_SECONDS.

    Replaces the previous "JWT as a ?token= query param" pattern used by
    both /ws/calls and /api/indoor-tracking/ws - a WS handshake can't
    carry a normal Authorization header from a browser, but the token in
    the URL landed in server/proxy access logs and browser history,
    letting anyone with log access replay a live session (call signaling
    identity, or worse, live location tracking) (/investigate 2026-09-20).
    Sending it as the first application message after connecting avoids
    that: it never appears in a URL, only in the WS frame itself.

    Returns None (caller must close the socket) on timeout, malformed
    envelope, or an invalid/expired token - never raises.
    """
    await websocket.accept()
    try:
        envelope = await asyncio.wait_for(
            websocket.receive_json(), timeout=AUTH_TIMEOUT_SECONDS
        )
    except Exception:
        # Covers a timed-out wait, a client disconnect before sending
        # anything, and a non-JSON first frame - all treated the same way:
        # no valid auth, caller closes the socket.
        return None

    if not isinstance(envelope, dict) or envelope.get("type") != "auth":
        return None
    token = envelope.get("token")
    if not isinstance(token, str):
        return None

    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username = payload.get("sub")
        if username is None:
            return None
    except jwt.PyJWTError:
        return None

    return db.query(models.User).filter(models.User.username == username).first()
