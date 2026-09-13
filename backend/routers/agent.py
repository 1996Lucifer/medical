from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from pydantic import BaseModel
from sqlalchemy.orm import Session
from typing import Any, Dict, List, Optional
import base64
import os
import tempfile
import fitz  # PyMuPDF

from database import get_db
import models
from routers.auth import get_current_user

# Import the new AI Gateway
import sys
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from services.gateway.ai_gateway import ai_gateway
from services.routing.intent_router import intent_router
from services.routing.llm_router import llm_router
from services.memory.memory_manager import memory_manager
from services.metrics.metrics import metrics_tracker

router = APIRouter(prefix="/api/agent", tags=["agent"])

# Roles allowed to view/manage any user's chat sessions, not just their own -
# mirrors the admin/superadmin override used elsewhere in this app's RBAC
# (see has_permission() in routers/auth.py).
_PRIVILEGED_ROLES = {"admin", "superadmin"}


def _assert_session_access(db: Session, session_id: str, current_user: models.User):
    """
    A session_id is plain client-generated text (a timestamp - see
    agent_provider.dart) with no secrecy guarantee, so ownership must be
    enforced server-side: whoever wrote the first message to a session_id
    owns it, and only that user (or a privileged role) may read/append/
    delete it. A session_id with no rows yet has no owner - anyone may
    start it.
    """
    if current_user.role in _PRIVILEGED_ROLES:
        return
    owner_id = memory_manager.get_session_owner(db, session_id)
    if owner_id is not None and owner_id != current_user.id:
        raise HTTPException(status_code=403, detail="You do not have access to this chat session.")


class ChartSpec(BaseModel):
    type: str
    title: str
    labels: List[str]
    values: List[float]


class ChatResponse(BaseModel):
    response: str
    intent: str
    engine: str
    chart: Optional[ChartSpec] = None

@router.post("/chat", response_model=ChatResponse)
async def chat_with_agent(
    message: str = Form(""),
    session_id: str = Form("default"),
    file: Optional[UploadFile] = File(None),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """
    Unified AI Agent endpoint powered by deterministic RAG pipeline and Multimodal support.
    """
    _assert_session_access(db, session_id, current_user)

    base64_img = None
    final_message = message

    if file:
        content = await file.read()
        filename = file.filename.lower()

        if filename.endswith(".pdf"):
            # Fast text extraction using PyMuPDF
            try:
                doc = fitz.open(stream=content, filetype="pdf")
                pdf_text = ""
                for page in doc:
                    pdf_text += page.get_text() + "\n"
                final_message = f"{message}\n\n[Attached Document Content]:\n{pdf_text}"
            except Exception as e:
                print(f"Error parsing PDF: {e}")
        elif filename.endswith((".png", ".jpg", ".jpeg")):
            # Image processing
            base64_img = base64.b64encode(content).decode('utf-8')

    # Let Gateway handle the entire workflow
    result = ai_gateway.handle_request(
        final_message,
        db,
        session_id,
        base64_img=base64_img,
        user_id=current_user.id,
        role=current_user.role,
    )

    # We still want to return intent and engine for the frontend UI
    intent = intent_router.detect_intent(final_message)
    engine = llm_router.route_to_model(intent) if not base64_img else "MedGemma (Vision)"

    return ChatResponse(
        response=result["text"],
        intent=intent,
        engine=engine,
        chart=result.get("chart"),
    )

from sqlalchemy import func

@router.get("/sessions")
async def get_all_sessions(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """
    Returns chat sessions ordered by most recent activity - the caller's own
    sessions only, unless they hold a privileged role (previously this
    listed every session for every user in the system, with no ownership
    filter at all).
    """
    query = db.query(
        models.ConversationHistory.session_id,
        func.max(models.ConversationHistory.timestamp).label('last_activity')
    )
    if current_user.role not in _PRIVILEGED_ROLES:
        query = query.filter(models.ConversationHistory.user_id == current_user.id)

    sessions = query.group_by(models.ConversationHistory.session_id)\
        .order_by(func.max(models.ConversationHistory.timestamp).desc())\
        .all()

    return {"sessions": [{"id": s.session_id, "last_activity": s.last_activity} for s in sessions]}

@router.get("/session/{session_id}")
async def get_session_details(
    session_id: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """
    Returns the full chronological history for a specific session.
    """
    _assert_session_access(db, session_id, current_user)
    history = memory_manager.get_history(db, session_id, limit=50) # fetch up to 50 for the UI
    return {"messages": history}

@router.delete("/session/{session_id}")
async def delete_session(
    session_id: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """
    Deletes a specific chat session and its history.
    """
    _assert_session_access(db, session_id, current_user)
    memory_manager.delete_session(db, session_id)
    return {"status": "success", "message": f"Session {session_id} deleted."}

@router.get("/history")
async def get_chat_history(
    session_id: str = "default",
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """
    Returns unique past user queries to populate UI suggestion chips dynamically.
    """
    _assert_session_access(db, session_id, current_user)
    history = memory_manager.get_history(db, session_id, limit=20)
    # Extract only unique user messages
    user_queries = []
    for msg in reversed(history): # Get most recent first
        if msg["role"] == "user" and msg["content"] not in user_queries:
            user_queries.append(msg["content"])
            if len(user_queries) >= 5: # Limit to 5 chips
                break
    return {"queries": user_queries}

@router.get("/usage")
async def get_agent_usage(current_user: models.User = Depends(get_current_user)):
    """
    Returns telemetry/usage logs to display in the UI.
    """
    # Return last 20 interactions reversed (most recent first)
    logs = list(reversed(metrics_tracker.logs))[:20]
    return {"usage": logs}
