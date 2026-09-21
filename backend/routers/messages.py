import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict
from sqlalchemy import or_
from sqlalchemy.orm import Session

from database import get_db
import models
from routers.auth import get_current_user
from routers.calls import get_connection
from services.calls.authorization import can_call
from services.calls.naming import display_name

router = APIRouter(prefix="/api/messages", tags=["messages"])


class MessageResponse(BaseModel):
    id: int
    sender_id: int
    recipient_id: int
    text: str
    created_at: datetime.datetime
    read_at: Optional[datetime.datetime]
    model_config = ConfigDict(from_attributes=True)


class SendMessageRequest(BaseModel):
    to: int
    text: str


class ConversationSummary(BaseModel):
    peer_id: int
    peer_name: str
    last_text: str
    last_at: datetime.datetime
    unread_count: int


@router.get("/conversations", response_model=List[ConversationSummary])
def list_conversations(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """
    One row per person the current user has ever exchanged a message with,
    most recent first, with an unread count - what the People Directory's
    per-contact message badge and (future) a dedicated inbox screen both
    need, without either fetching full history up front.
    """
    rows = (
        db.query(models.StaffMessage)
        .filter(
            or_(
                models.StaffMessage.sender_id == current_user.id,
                models.StaffMessage.recipient_id == current_user.id,
            )
        )
        .order_by(models.StaffMessage.created_at.desc())
        .all()
    )

    by_peer: dict[int, ConversationSummary] = {}
    unread_by_peer: dict[int, int] = {}
    for row in rows:
        peer_id = (
            row.recipient_id if row.sender_id == current_user.id else row.sender_id
        )
        if row.recipient_id == current_user.id and row.read_at is None:
            unread_by_peer[peer_id] = unread_by_peer.get(peer_id, 0) + 1
        if peer_id not in by_peer:
            peer_user = (
                row.recipient if row.sender_id == current_user.id else row.sender
            )
            by_peer[peer_id] = ConversationSummary(
                peer_id=peer_id,
                peer_name=display_name(db, peer_user) if peer_user else "Unknown",
                last_text=row.text,
                last_at=row.created_at,
                unread_count=0,
            )

    return [
        summary.model_copy(update={"unread_count": unread_by_peer.get(peer_id, 0)})
        for peer_id, summary in by_peer.items()
    ]


@router.get("/with/{peer_id}", response_model=List[MessageResponse])
def get_conversation(
    peer_id: int,
    limit: int = 100,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    if not can_call(db, current_user, peer_id):
        raise HTTPException(
            status_code=403, detail="You are not permitted to message this person."
        )

    rows = (
        db.query(models.StaffMessage)
        .filter(
            or_(
                (models.StaffMessage.sender_id == current_user.id)
                & (models.StaffMessage.recipient_id == peer_id),
                (models.StaffMessage.sender_id == peer_id)
                & (models.StaffMessage.recipient_id == current_user.id),
            )
        )
        .order_by(models.StaffMessage.created_at.asc())
        .limit(limit)
        .all()
    )
    return rows


@router.post("", response_model=MessageResponse)
async def send_message(
    body: SendMessageRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    text = body.text.strip()
    if not text:
        raise HTTPException(status_code=400, detail="Message text cannot be empty.")

    if not can_call(db, current_user, body.to):
        raise HTTPException(
            status_code=403, detail="You are not permitted to message this person."
        )

    row = models.StaffMessage(
        sender_id=current_user.id, recipient_id=body.to, text=text
    )
    db.add(row)
    db.commit()
    db.refresh(row)

    # Best-effort live push - persistence above is what actually guarantees
    # delivery; this just avoids the recipient having to poll/re-open the
    # chat to see a message that arrives while they're already looking at
    # it.
    target = get_connection(body.to)
    if target is not None:
        try:
            await target.send_json(
                {
                    "type": "message",
                    "id": row.id,
                    "from": current_user.id,
                    "to": body.to,
                    "text": text,
                    "created_at": row.created_at.isoformat(),
                }
            )
        except Exception:
            pass

    return row


@router.post("/with/{peer_id}/read")
def mark_read(
    peer_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    now = datetime.datetime.now(datetime.timezone.utc)
    updated = (
        db.query(models.StaffMessage)
        .filter(
            models.StaffMessage.sender_id == peer_id,
            models.StaffMessage.recipient_id == current_user.id,
            models.StaffMessage.read_at.is_(None),
        )
        .update({"read_at": now})
    )
    db.commit()
    return {"marked_read": updated}
