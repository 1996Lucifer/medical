from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from pydantic import BaseModel
from sqlalchemy.orm import Session
from typing import Optional
import base64
import os
import tempfile
import fitz  # PyMuPDF

from database import get_db
from routers.auth import get_current_user
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
    # current_user: models.User = Depends(get_current_user) # Disabled for testing
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

@router.get("/history")
async def get_chat_history(session_id: str = "default"):
    """
    Returns unique past user queries to populate UI suggestion chips dynamically.
    """
    history = memory_manager.get_history(session_id)
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

