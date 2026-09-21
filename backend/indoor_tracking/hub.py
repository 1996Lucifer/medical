"""
In-memory live indoor-tracking state.

Deliberately NOT backed by the database: per-fix positions are never
persisted (product decision — live only, no location history). This module
holds exactly the current + previous point per active attendance session,
and broadcasts updates to connected Super Admin WebSocket clients. If the
process restarts, all live tracking state is lost and rebuilt naturally as
signals keep arriving — that's an accepted trade-off of not persisting.
"""
import asyncio
import datetime
import threading
from dataclasses import dataclass, field
from typing import Dict, Optional, Set


@dataclass
class TrackingState:
    attendance_session_id: int
    staff_id: Optional[int]
    staff_name: str
    department: Optional[str]

    floor_id: Optional[int] = None
    x: Optional[float] = None
    y: Optional[float] = None
    prev_x: Optional[float] = None
    prev_y: Optional[float] = None
    area_name: Optional[str] = None
    accuracy_m: Optional[float] = None
    confidence: Optional[float] = None
    source: Optional[str] = None

    # "active" | "paused_outside_geofence" | "stopped"
    status: str = "active"
    tracking_started_at: datetime.datetime = field(
        default_factory=lambda: datetime.datetime.now(tz=datetime.timezone.utc)
    )
    updated_at: datetime.datetime = field(
        default_factory=lambda: datetime.datetime.now(tz=datetime.timezone.utc)
    )

    def to_dict(self) -> dict:
        return {
            "attendance_session_id": self.attendance_session_id,
            "staff_id": self.staff_id,
            "staff_name": self.staff_name,
            "department": self.department,
            "floor_id": self.floor_id,
            "x": self.x,
            "y": self.y,
            "area_name": self.area_name,
            "accuracy_m": self.accuracy_m,
            "confidence": self.confidence,
            "source": self.source,
            "status": self.status,
            "tracking_started_at": self.tracking_started_at.isoformat(),
            "updated_at": self.updated_at.isoformat(),
        }


class IndoorTrackingHub:
    def __init__(self):
        self._sessions: Dict[int, TrackingState] = {}
        self._lock = threading.Lock()
        # floor_id -> set of connected super-admin websockets watching it
        self._watchers: Dict[int, Set] = {}
        self._loop: Optional[asyncio.AbstractEventLoop] = None

    # ── Connection management (mirrors events.py's EventEngine pattern) ──
    def connect(self, websocket, floor_id: int):
        if self._loop is None:
            self._loop = asyncio.get_running_loop()
        with self._lock:
            self._watchers.setdefault(floor_id, set()).add(websocket)

    def disconnect(self, websocket, floor_id: int):
        with self._lock:
            self._watchers.get(floor_id, set()).discard(websocket)

    def _broadcast(self, floor_id: int, event: dict):
        loop = self._loop
        if loop is None:
            return
        with self._lock:
            sockets = list(self._watchers.get(floor_id, set()))
        for ws in sockets:
            try:
                asyncio.run_coroutine_threadsafe(ws.send_json(event), loop)
            except Exception:
                pass

    # ── Session lifecycle ────────────────────────────────────────────────
    def start_session(
        self,
        attendance_session_id: int,
        staff_id: Optional[int],
        staff_name: str,
        department: Optional[str],
    ) -> None:
        with self._lock:
            if attendance_session_id in self._sessions:
                return
            self._sessions[attendance_session_id] = TrackingState(
                attendance_session_id=attendance_session_id,
                staff_id=staff_id,
                staff_name=staff_name,
                department=department,
            )

    def stop_session(self, attendance_session_id: int) -> None:
        with self._lock:
            state = self._sessions.pop(attendance_session_id, None)
        if state is not None:
            state.status = "stopped"
            self._broadcast(
                state.floor_id or -1, {"type": "session_stopped", "data": state.to_dict()}
            )

    def get_session(self, attendance_session_id: int) -> Optional[TrackingState]:
        with self._lock:
            return self._sessions.get(attendance_session_id)

    def is_active(self, attendance_session_id: int) -> bool:
        with self._lock:
            return attendance_session_id in self._sessions

    def update_position(
        self,
        attendance_session_id: int,
        *,
        floor_id: int,
        x: float,
        y: float,
        area_name: Optional[str],
        accuracy_m: float,
        confidence: float,
        source: str,
        status: str = "active",
    ) -> Optional[TrackingState]:
        with self._lock:
            state = self._sessions.get(attendance_session_id)
            if state is None:
                return None
            prev_floor = state.floor_id
            state.prev_x, state.prev_y = state.x, state.y
            state.floor_id = floor_id
            state.x, state.y = x, y
            state.area_name = area_name
            state.accuracy_m = accuracy_m
            state.confidence = confidence
            state.source = source
            state.status = status
            state.updated_at = datetime.datetime.now(tz=datetime.timezone.utc)
            snapshot = state.to_dict()

        self._broadcast(floor_id, {"type": "position_update", "data": snapshot})
        if prev_floor is not None and prev_floor != floor_id:
            self._broadcast(prev_floor, {"type": "session_left_floor", "data": snapshot})
        return state

    def set_status(self, attendance_session_id: int, status: str) -> None:
        """Flip status (e.g. active -> paused_outside_geofence) without a
        new position — used when gating decides to pause/resume without a
        fresh fused fix."""
        with self._lock:
            state = self._sessions.get(attendance_session_id)
            if state is None:
                return
            state.status = status
            state.updated_at = datetime.datetime.now(tz=datetime.timezone.utc)
            floor_id = state.floor_id
            snapshot = state.to_dict()
        if floor_id is not None:
            self._broadcast(floor_id, {"type": "status_update", "data": snapshot})

    def snapshot(self, floor_id: int) -> list:
        with self._lock:
            return [
                s.to_dict() for s in self._sessions.values() if s.floor_id == floor_id
            ]


hub = IndoorTrackingHub()
