import os
import shutil
from datetime import datetime
from typing import List

import models
from database import engine, get_db
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from google import genai
from pydantic import BaseModel, ConfigDict
from sqlalchemy.orm import Session

from sqlalchemy import text

# Create database tables and vector extension
with engine.connect() as conn:
    conn.execute(text("CREATE EXTENSION IF NOT EXISTS vector"))
    conn.commit()

models.Base.metadata.create_all(bind=engine)

load_dotenv()

from camera import routes as camera_routes
from routers import staff, camera_api, attendance, equipment, events

app = FastAPI(title="AI Discharge Summary Generator")

# Include all modular routers
app.include_router(camera_routes.router)
app.include_router(staff.router)
app.include_router(camera_api.router)
app.include_router(attendance.router)
app.include_router(equipment.router)
app.include_router(events.router)

# Allow CORS for Flutter app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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


@app.post("/api/consultations", response_model=ConsultationResponse)
async def upload_audio(
    patient_name: str, file: UploadFile = File(...), db: Session = Depends(get_db)
):
    if not GENAI_API_KEY:
        raise HTTPException(status_code=500, detail="Gemini API Key is not configured")

    # Save the uploaded audio file temporarily
    temp_file_path = f"temp_{file.filename}"
    try:
        with open(temp_file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        # Upload the audio file to Gemini
        gemini_file = client.files.upload(file=temp_file_path)

        # Prompt for the model
        prompt = """
        You are a highly skilled medical AI assistant.
        Listen to the following doctor-patient consultation audio.
        First, provide a full transcript of the conversation.
        Then, generate a structured Medical Discharge Summary based on the consultation.

        Output format:
        TRANSCRIPT:
        [full transcript here]

        DISCHARGE SUMMARY:
        [structured summary including Chief Complaint, History of Present Illness, Assessment, and Plan]
        """

        # We use gemini-2.5-flash as it is free-tier eligible, fast, and supports multimodal (audio) input
        response = client.models.generate_content(
            model="gemini-2.5-flash", contents=[prompt, gemini_file]
        )

        # Parse the response (basic parsing based on the prompt structure)
        text_response = response.text
        transcript_part = ""
        summary_part = ""

        if "DISCHARGE SUMMARY:" in text_response:
            parts = text_response.split("DISCHARGE SUMMARY:")
            transcript_part = parts[0].replace("TRANSCRIPT:", "").strip()
            summary_part = parts[1].strip()
        else:
            summary_part = text_response.strip()

        # Save to database
        db_consultation = models.Consultation(
            patient_name=patient_name,
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
        db
        .query(models.Consultation)
        .order_by(models.Consultation.date.desc())
        .offset(skip)
        .limit(limit)
        .all()
    )
    return consultations
