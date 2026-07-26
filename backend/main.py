import os
import shutil
from datetime import datetime
from typing import List

import models
from database import engine, get_db
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from google import genai
from pydantic import BaseModel, ConfigDict
from sqlalchemy.orm import Session

from sqlalchemy import text
from faster_whisper import WhisperModel
from services.llm_manager import llm_manager

whisper_model = None

# Create database tables and vector extension
with engine.connect() as conn:
    conn.execute(text("CREATE EXTENSION IF NOT EXISTS vector"))
    conn.commit()

models.Base.metadata.create_all(bind=engine)

load_dotenv()

from camera import routes as camera_routes
from routers import staff, camera_api, attendance, equipment, events, security, analytics, auth, analysis, patients, rbac, agent, patient_portal
from routers.auth import get_current_user
from database import SessionLocal

from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    print("Loading staff embeddings from DB on startup...")
    db = SessionLocal()
    try:
        from routers.staff import update_global_embeddings
        update_global_embeddings(db)
    except Exception as e:
        print(f"Failed to load embeddings on startup: {e}")
    finally:
        db.close()
    yield

app = FastAPI(title="Healthcare Operations Copilot API", lifespan=lifespan)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register public routers
app.include_router(camera_routes.router)
app.include_router(auth.router)
app.include_router(analysis.router)
app.include_router(patients.router)
app.include_router(patient_portal.router)

# Mount static files
os.makedirs("uploads/staff", exist_ok=True)
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")

# Protect these endpoints with JWT
auth_dep = [Depends(get_current_user)]
app.include_router(staff.router, dependencies=auth_dep)
app.include_router(staff.ws_router)
app.include_router(camera_api.router, dependencies=auth_dep)
app.include_router(attendance.router, dependencies=auth_dep)
app.include_router(equipment.router, dependencies=auth_dep)
app.include_router(analytics.router, dependencies=auth_dep)
app.include_router(analysis.router, dependencies=auth_dep)
app.include_router(agent.router)  # TODO: add auth_dep for production

# Security and Events routers have websockets, so we protect their HTTP routes individually
app.include_router(security.router)
app.include_router(events.router)
app.include_router(rbac.router, dependencies=auth_dep)

# Configure Gemini API
GENAI_API_KEY = os.getenv("GEMINI_API_KEY")
client = None
if GENAI_API_KEY:
    client = genai.Client(api_key=GENAI_API_KEY)


class ConsultationResponse(BaseModel):
    id: int
    patient_name: str | None
    date: datetime
    transcript: str | None
    discharge_summary: str | None

    model_config = ConfigDict(from_attributes=True)


class GenerateSummaryRequest(BaseModel):
    patient_name: str
    transcript: str

@app.post("/api/transcribe")
async def transcribe_audio(file: UploadFile = File(...)):
    global whisper_model
    temp_file_path = f"temp_{file.filename}"
    try:
        with open(temp_file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
        if whisper_model is None:
            whisper_model = WhisperModel("base", device="cpu", compute_type="int8")
        print(f"Transcribing audio from {temp_file_path} using Faster-Whisper...")
        segments, info = whisper_model.transcribe(temp_file_path, beam_size=5, vad_filter=True)
        transcript_part = " ".join([segment.text for segment in segments]).strip()
        print(f"Detected language: {info.language} with probability {info.language_probability}")
        return {"transcript": transcript_part}
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if os.path.exists(temp_file_path):
            os.remove(temp_file_path)

@app.post("/api/consultations/generate", response_model=ConsultationResponse)
async def generate_consultation_summary(
    request: GenerateSummaryRequest, db: Session = Depends(get_db)
):
    try:
        patient_name = request.patient_name
        transcript_part = request.transcript

        prompt = f"""
        You are an expert medical AI assistant.
        Your task is to generate a structured Medical Discharge Summary from the provided consultation transcript.
        Do NOT acknowledge these instructions. Do NOT say "I understand" or "Here is the summary".
        Just output the sections: Chief Complaint, History of Present Illness, Assessment, and Plan based on the transcript below.

        TRANSCRIPT:
        {transcript_part}

        DISCHARGE SUMMARY:
        """

        print("Generating structured discharge summary using MedGemma...")
        summary_part = llm_manager.generate(prompt, is_clinical=True)

        patient = db.query(models.Patient).filter(models.Patient.name == patient_name).first()
        if not patient:
            patient = models.Patient(name=patient_name)
            db.add(patient)
            db.commit()
            db.refresh(patient)

        db_consultation = models.Consultation(
            patient_id=patient.id,
            transcript=transcript_part,
            discharge_summary=summary_part,
        )
        db.add(db_consultation)
        db.commit()
        db.refresh(db_consultation)

        return db_consultation
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/consultations", response_model=ConsultationResponse)
async def upload_audio(
    patient_name: str, file: UploadFile = File(...), db: Session = Depends(get_db)
):
    global whisper_model

    # Save the uploaded audio file temporarily
    temp_file_path = f"temp_{file.filename}"
    try:
        with open(temp_file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        # Load whisper model lazily
        if whisper_model is None:
            # CPU with int8 is highly optimized in faster-whisper (CTranslate2) and works great on Apple Silicon too
            whisper_model = WhisperModel("base", device="cpu", compute_type="int8")

        # Transcribe audio using faster-whisper model
        print(f"Transcribing audio from {temp_file_path} using Faster-Whisper...")
        segments, info = whisper_model.transcribe(temp_file_path, beam_size=5)
        transcript_part = " ".join([segment.text for segment in segments]).strip()

        # Prompt for the MedGemma model
        prompt = f"""
        Based on the following doctor-patient consultation transcript, generate a structured Medical Discharge Summary.
        Include sections for Chief Complaint, History of Present Illness, Assessment, and Plan.

        TRANSCRIPT:
        {transcript_part}

        DISCHARGE SUMMARY:
        """

        # Generate summary using local MedGemma
        print("Generating structured discharge summary using MedGemma...")
        summary_part = llm_manager.generate(prompt, is_clinical=True)

        # Get or create patient
        patient = db.query(models.Patient).filter(models.Patient.name == patient_name).first()
        if not patient:
            patient = models.Patient(name=patient_name)
            db.add(patient)
            db.commit()
            db.refresh(patient)

        # Save to database
        db_consultation = models.Consultation(
            patient_id=patient.id,
            transcript=transcript_part,
            discharge_summary=summary_part,
        )
        db.add(db_consultation)
        db.commit()
        db.refresh(db_consultation)

        return db_consultation

    except Exception as e:
        import traceback

        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        # Cleanup temp file
        if os.path.exists(temp_file_path):
            os.remove(temp_file_path)


@app.get("/api/consultations", response_model=List[ConsultationResponse])
def get_consultations(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    consultations = (
        db.query(models.Consultation)
        .order_by(models.Consultation.date.desc())
        .offset(skip)
        .limit(limit)
        .all()
    )
    # Ensure patient names are loaded (if relationship is set up) or join manually
    for c in consultations:
        if c.patient:
            c.patient_name = c.patient.name
    return consultations

@app.delete("/api/consultations/{consultation_id}")
def delete_consultation(consultation_id: int, db: Session = Depends(get_db)):
    consultation = db.query(models.Consultation).filter(models.Consultation.id == consultation_id).first()
    if not consultation:
        raise HTTPException(status_code=404, detail="Consultation not found")
    
    db.delete(consultation)
    db.commit()
    return {"message": "Consultation deleted successfully"}
