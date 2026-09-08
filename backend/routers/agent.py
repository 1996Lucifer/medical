from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from pydantic import BaseModel
from sqlalchemy.orm import Session
from typing import Optional
import base64
import os
import tempfile
import fitz  # PyMuPDF

from database import get_db
import models

# Import the new AI Gateway
import sys
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from services.gateway.ai_gateway import ai_gateway
from services.routing.intent_router import intent_router
from services.routing.llm_router import llm_router
from services.memory.memory_manager import memory_manager
from services.metrics.metrics import metrics_tracker

router = APIRouter(prefix="/api/agent", tags=["agent"])

class ChatResponse(BaseModel):
    response: str
    intent: str
    engine: str

@router.post("/chat", response_model=ChatResponse)
async def chat_with_agent(
    message: str = Form(""),
    session_id: str = Form("default"),
    file: Optional[UploadFile] = File(None),
    db: Session = Depends(get_db),
    # Auth is enforced at the router level (main.py: dependencies=auth_dep on
    # agent.router) rather than per-route here.
):
    """
    Unified AI Agent endpoint powered by deterministic RAG pipeline and Multimodal support.
    """
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
    response_text = ai_gateway.handle_request(final_message, db, session_id, base64_img=base64_img)
    
    # We still want to return intent and engine for the frontend UI
    intent = intent_router.detect_intent(final_message)
    engine = llm_router.route_to_model(intent) if not base64_img else "MedGemma (Vision)"
    
    return ChatResponse(
        response=response_text,
        intent=intent,
        engine=engine
    )

from sqlalchemy import func

@router.get("/sessions")
async def get_all_sessions(db: Session = Depends(get_db)):
    """
    Returns a list of all distinct chat sessions ordered by most recent activity.
    """
    # Fetch distinct session_ids and their max timestamp
    sessions = db.query(
        models.ConversationHistory.session_id,
        func.max(models.ConversationHistory.timestamp).label('last_activity')
    ).group_by(models.ConversationHistory.session_id)\
     .order_by(func.max(models.ConversationHistory.timestamp).desc())\
     .all()
     
    # Return as list of strings or objects, let's return a list of dicts
    return {"sessions": [{"id": s.session_id, "last_activity": s.last_activity} for s in sessions]}

@router.get("/session/{session_id}")
async def get_session_details(session_id: str, db: Session = Depends(get_db)):
    """
    Returns the full chronological history for a specific session.
    """
    history = memory_manager.get_history(db, session_id, limit=50) # fetch up to 50 for the UI
    return {"messages": history}

@router.delete("/session/{session_id}")
async def delete_session(session_id: str, db: Session = Depends(get_db)):
    """
    Deletes a specific chat session and its history.
    """
    memory_manager.delete_session(db, session_id)
    return {"status": "success", "message": f"Session {session_id} deleted."}

@router.get("/history")
async def get_chat_history(session_id: str = "default", db: Session = Depends(get_db)):
    """
    Returns unique past user queries to populate UI suggestion chips dynamically.
    """
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
async def get_agent_usage():
    """
    Returns telemetry/usage logs to display in the UI.
    """
    # Return last 20 interactions reversed (most recent first)
    logs = list(reversed(metrics_tracker.logs))[:20]
    return {"usage": logs}

