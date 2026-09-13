import os
import re
import shutil
from datetime import datetime

import jwt
import models
from database import engine, get_db
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from faster_whisper import WhisperModel
from google import genai
from pydantic import BaseModel, ConfigDict
from services.llm_manager import llm_manager
from sqlalchemy import text
from sqlalchemy.orm import Session
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse

whisper_model = None


def _get_whisper_device():
    try:
        import torch

        if torch.cuda.is_available():
            return "cuda", "float16"
    except Exception:
        pass
    return "cpu", "int8"


# Create database tables and vector extension
with engine.connect() as conn:
    try:
        conn.execute(text("CREATE EXTENSION IF NOT EXISTS vector"))
        conn.commit()
    except Exception as e:
        print(f"Skipping vector extension creation: {e}")

# TODO(migrations): now that alembic/ is set up (see backend/alembic/), this
# should become `alembic upgrade head` instead — create_all() only adds
# brand-new tables and silently does nothing for column/type changes to
# existing ones, which is why alter_db.py/migrate_db.py/backfill_db.py exist
# as hand-run patches. Left as-is until the DB has been bootstrapped onto
# alembic (run once, against the live DB: `alembic stamp head` if the schema
# already matches models.py, or `alembic upgrade head` on a fresh DB) —
# removing this before that bootstrap would leave a fresh deploy with no
# tables at all.
models.Base.metadata.create_all(bind=engine)

load_dotenv(override=False)

from contextlib import asynccontextmanager

from camera import routes as camera_routes
from database import SessionLocal
from routers import (
    agent,
    analysis,
    analytics,
    attendance,
    auth,
    calls,
    camera_api,
    equipment,
    events,
    patient_portal,
    patients,
    rbac,
    rfid,
    security,
    setup,
    site_config,
    staff,
)
from routers.auth import get_current_user, require_permission


@asynccontextmanager
async def lifespan(app: FastAPI):
    import asyncio
    import subprocess
    
    print("Cleaning up any orphaned background processes...")
    try:
        subprocess.run(["pkill", "-f", "spawn_main"], capture_output=True)
    except Exception:
        pass

    db = SessionLocal()
    try:
        rfid.ensure_fixed_station(db)
    except Exception as e:
        print(f"Failed to provision fixed RFID station from env: {e}")
    finally:
        db.close()

    def load_embeddings_in_background():
        print("Loading staff embeddings from DB in background...")
        db = SessionLocal()
        try:
            from routers.staff import update_global_embeddings

            update_global_embeddings(db)
            print("Successfully loaded staff embeddings.")
        except Exception as e:
            print(f"Failed to load embeddings on startup: {e}")
        finally:
            db.close()

    # Shift work to a background thread so the server goes up immediately
    asyncio.create_task(asyncio.to_thread(load_embeddings_in_background))
    yield


app = FastAPI(title="Healthcare Operations Copilot API", lifespan=lifespan)


class AuthenticatedStaticFilesMiddleware(BaseHTTPMiddleware):
    """
    Gates /uploads (staff photos, incident snapshots) behind the same JWT used
    everywhere else. StaticFiles doesn't support FastAPI `dependencies=`, so
    this mirrors auth.get_current_user's checks at the ASGI layer instead of
    leaving the mount fully public.

    Exception: /uploads/branding/* (hospital logo) is intentionally public —
    it's shown on the pre-login screen (site_config.router's GET is public by
    design, see routers/site_config.py) and there's no token to attach yet at
    that point in the flow.
    """

    PUBLIC_PREFIXES = ("/uploads/branding/",)

    async def dispatch(self, request: Request, call_next):
        if request.url.path.startswith("/uploads") and not request.url.path.startswith(
            self.PUBLIC_PREFIXES
        ):
            auth_header = request.headers.get("Authorization", "")
            token = (
                auth_header[7:]
                if auth_header.lower().startswith("bearer ")
                else None
            )
            if not token:
                return JSONResponse(
                    {"detail": "Not authenticated"}, status_code=401
                )
            try:
                payload = jwt.decode(
                    token, auth.SECRET_KEY, algorithms=[auth.ALGORITHM]
                )
                username = payload.get("sub")
                if not username:
                    raise jwt.PyJWTError("missing sub claim")
            except jwt.PyJWTError:
                return JSONResponse(
                    {"detail": "Could not validate credentials"}, status_code=401
                )

            db = SessionLocal()
            try:
                user = (
                    db.query(models.User)
                    .filter(models.User.username == username)
                    .first()
                )
            finally:
                db.close()
            if not user:
                return JSONResponse(
                    {"detail": "Could not validate credentials"}, status_code=401
                )
        return await call_next(request)


# Registered before CORS so CORS ends up as the outermost layer (added last =
# outermost in Starlette) — this way 401 responses from the check above still
# carry CORS headers instead of surfacing as opaque browser CORS failures.
app.add_middleware(AuthenticatedStaticFilesMiddleware)

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
app.include_router(
    site_config.router
)  # GET is public; mutations check superadmin in-router
# Public (no user exists yet on a fresh deployment) but /initialize is a
# one-shot guarded internally — see routers/setup.py.
app.include_router(setup.router)

# Mount static files. StaticFiles doesn't support `dependencies=`, so /uploads is
# gated by AuthenticatedStaticFilesMiddleware below instead (checks the same JWT
# as auth_dep) rather than being left public.
os.makedirs("uploads/staff", exist_ok=True)
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")

# Protect these endpoints with JWT
auth_dep = [Depends(get_current_user)]
app.include_router(staff.router, dependencies=auth_dep)
app.include_router(staff.ws_router)
app.include_router(calls.router)
app.include_router(camera_api.router, dependencies=auth_dep)
app.include_router(attendance.router, dependencies=auth_dep)
app.include_router(equipment.router, dependencies=auth_dep)
app.include_router(analytics.router, dependencies=auth_dep)
app.include_router(analysis.router, dependencies=auth_dep)
app.include_router(agent.router, dependencies=auth_dep)
app.include_router(patients.router, dependencies=auth_dep)
app.include_router(patient_portal.router, dependencies=auth_dep)

# Security and Events routers have websockets, so we protect their HTTP routes individually
app.include_router(security.router)
app.include_router(events.router)
# RBAC management (role/permission assignment) requires superadmin or an explicit
# "manage_rbac" grant, not just being logged in — this was previously reachable by
# any authenticated user, including a self-service privilege escalation to superadmin.
app.include_router(
    rbac.router,
    dependencies=auth_dep + [Depends(require_permission("manage_rbac"))],
)
# RFID router mixes two auth kinds on purpose: /devices and /enroll-sessions/*
# require an admin JWT (checked per-route via require_permission("manage_devices")),
# while /enroll and /verify are called by unauthenticated physical devices and
# check a device bearer key instead (see routers/rfid.py::get_current_device) —
# so this router is intentionally NOT mounted with `dependencies=auth_dep`.
app.include_router(rfid.router)

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
    staff_name: str | None = None
    staff_role: str | None = None

    model_config = ConfigDict(from_attributes=True)


class GenerateSummaryRequest(BaseModel):
    patient_name: str
    transcript: str


@app.post("/api/transcribe", dependencies=auth_dep)
async def transcribe_audio(file: UploadFile = File(...)):
    global whisper_model
    temp_file_path = f"temp_{file.filename}"
    try:
        with open(temp_file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
        if whisper_model is None:
            w_dev, w_type = _get_whisper_device()
            whisper_model = WhisperModel("base", device=w_dev, compute_type=w_type)
        print(f"Transcribing audio from {temp_file_path} using Faster-Whisper...")
        segments, info = whisper_model.transcribe(
            temp_file_path, beam_size=5, vad_filter=True
        )
        transcript_part = " ".join([segment.text for segment in segments]).strip()
        print(
            f"Detected language: {info.language} with probability {info.language_probability}"
        )
        return {"transcript": transcript_part}
    except Exception as e:
        import traceback

        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if os.path.exists(temp_file_path):
            os.remove(temp_file_path)


# A real clinical transcript, even a brief one, reads like actual speech
# ("Patient reports mild headache...") - a handful of words. Below this, the
# model has nothing to summarize and (observed in production data) tends to
# respond with its own planning/acknowledgment text instead of a summary,
# which then gets saved and shown to the patient as their medical record.
MIN_TRANSCRIPT_WORDS = 6

# Phrases seen when the model describes what it's ABOUT to do instead of
# actually doing it - a `- transcript too short` case slips past the prompt
# instruction, so this is the output-side half of the guardrail.
_PREAMBLE_PATTERNS = (
    "i understand",
    "i will generate",
    "i will focus",
    "here's the structure",
    "i am ready",
    "once i have it",
    "please provide the transcript",
)


def _looks_like_preamble(summary: str) -> bool:
    lowered = summary.strip().lower()
    return any(lowered.startswith(p) or p in lowered[:200] for p in _PREAMBLE_PATTERNS)


def _generate_discharge_summary(transcript: str) -> str:
    """
    Shared by both the typed-transcript and audio-upload consultation
    endpoints so they can't drift into inconsistent prompts (one had the
    anti-preamble instruction, the other didn't) or inconsistent validation
    (neither had any). Raises HTTPException on input that's too thin to
    summarize, or output that's clearly the model describing its task
    instead of doing it - both cases where the old code silently saved
    whatever came back and showed it to the patient as a real summary.
    """
    if len(transcript.split()) < MIN_TRANSCRIPT_WORDS:
        raise HTTPException(
            status_code=400,
            detail=(
                "Transcript is too short to generate a discharge summary "
                f"(need at least {MIN_TRANSCRIPT_WORDS} words of real content)."
            ),
        )

    prompt = f"""
    You are an expert medical AI assistant.
    Your task is to generate a structured Medical Discharge Summary from the provided consultation transcript.
    Do NOT acknowledge these instructions. Do NOT say "I understand" or "Here is the summary".
    Just output the sections: Chief Complaint, History of Present Illness, Assessment, and Plan based on the transcript below.

    TRANSCRIPT:
    {transcript}

    DISCHARGE SUMMARY:
    """

    print("Generating structured discharge summary using MedGemma...")
    summary = llm_manager.generate(prompt, is_clinical=True)

    if _looks_like_preamble(summary):
        raise HTTPException(
            status_code=502,
            detail="The model did not produce a usable summary for this transcript - please try again.",
        )

    # Even on a good transcript, the model routinely prefixes real content
    # with a conversational lead-in ("Okay, here's a summary of..."). The
    # prompt already asks it not to; it does it anyway. Rather than reject
    # otherwise-good output, strip everything before the first section
    # heading the prompt actually asked for, so a patient reads a clean
    # document instead of the model narrating itself.
    match = re.search(r"\*\*Chief Complaint", summary, re.IGNORECASE)
    if match and match.start() > 0:
        summary = summary[match.start():]

    return summary.strip()


@app.post(
    "/api/consultations/generate",
    response_model=ConsultationResponse,
    dependencies=auth_dep,
)
async def generate_consultation_summary(
    request: GenerateSummaryRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    try:
        patient_name = request.patient_name
        transcript_part = request.transcript
        summary_part = _generate_discharge_summary(transcript_part)

        patient = (
            db.query(models.Patient).filter(models.Patient.name == patient_name).first()
        )
        if not patient:
            patient = models.Patient(name=patient_name)
            db.add(patient)
            db.commit()
            db.refresh(patient)

        attending_staff = (
            db.query(models.Staff).filter(models.Staff.user_id == current_user.id).first()
        )

        db_consultation = models.Consultation(
            patient_id=patient.id,
            staff_id=attending_staff.id if attending_staff else None,
            transcript=transcript_part,
            discharge_summary=summary_part,
        )
        db.add(db_consultation)
        db.commit()
        db.refresh(db_consultation)

        return db_consultation
    except HTTPException:
        raise
    except Exception as e:
        import traceback

        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))


@app.post(
    "/api/consultations", response_model=ConsultationResponse, dependencies=auth_dep
)
async def upload_audio(
    patient_name: str,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    global whisper_model

    # Save the uploaded audio file temporarily
    temp_file_path = f"temp_{file.filename}"
    try:
        with open(temp_file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        # Load whisper model lazily
        if whisper_model is None:
            w_dev, w_type = _get_whisper_device()
            whisper_model = WhisperModel("base", device=w_dev, compute_type=w_type)

        # Transcribe audio using faster-whisper model
        print(f"Transcribing audio from {temp_file_path} using Faster-Whisper...")
        segments, info = whisper_model.transcribe(temp_file_path, beam_size=5)
        transcript_part = " ".join([segment.text for segment in segments]).strip()

        summary_part = _generate_discharge_summary(transcript_part)

        # Get or create patient
        patient = (
            db.query(models.Patient).filter(models.Patient.name == patient_name).first()
        )
        if not patient:
            patient = models.Patient(name=patient_name)
            db.add(patient)
            db.commit()
            db.refresh(patient)

        attending_staff = (
            db.query(models.Staff).filter(models.Staff.user_id == current_user.id).first()
        )

        # Save to database
        db_consultation = models.Consultation(
            patient_id=patient.id,
            staff_id=attending_staff.id if attending_staff else None,
            transcript=transcript_part,
            discharge_summary=summary_part,
        )
        db.add(db_consultation)
        db.commit()
        db.refresh(db_consultation)

        return db_consultation

    except HTTPException:
        raise
    except Exception as e:
        import traceback

        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        # Cleanup temp file
        if os.path.exists(temp_file_path):
            os.remove(temp_file_path)


@app.get(
    "/api/consultations",
    response_model=list[ConsultationResponse],
    dependencies=auth_dep,
)
def get_consultations(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    consultations = (
        db
        .query(models.Consultation)
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


@app.delete("/api/consultations/{consultation_id}", dependencies=auth_dep)
def delete_consultation(consultation_id: int, db: Session = Depends(get_db)):
    consultation = (
        db
        .query(models.Consultation)
        .filter(models.Consultation.id == consultation_id)
        .first()
    )
    if not consultation:
        raise HTTPException(status_code=404, detail="Consultation not found")

    db.delete(consultation)
    db.commit()
    return {"message": "Consultation deleted successfully"}
