from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel
from sqlalchemy.orm import Session
from typing import Optional
import json
import base64
import os
import datetime

from database import get_db
from routers.auth import get_current_user
import models
from services.llm_manager import llm_manager

router = APIRouter(prefix="/api/analysis", tags=["analysis"])

# This endpoint accepts a photo/scan of a medical report or a PDF of one
# (see the PDF-vs-image branch below) and hands it to the LLM - anything
# else, or anything oversized, should be rejected before that happens.
MAX_UPLOAD_SIZE_BYTES = 20 * 1024 * 1024  # 20MB
ALLOWED_UPLOAD_CONTENT_TYPES = {
    "image/jpeg", "image/png", "image/webp", "application/pdf",
}

class SaveReportRequest(BaseModel):
    patient_name: str
    key_findings: str
    abnormalities: str
    recommendations: str
    # Optional secondary identifiers - if supplied (or previously extracted
    # from the document) they're used to confirm which existing Patient row
    # (if any) this report belongs to, so two different patients who happen
    # to share a name are never merged together. See _resolve_patient below.
    mrn: Optional[str] = None
    dob: Optional[str] = None
    # If the caller already resolved the ambiguity itself (e.g. the admin
    # explicitly picked a patient from a "did you mean" list after an
    # earlier 409), it can pass the exact patient id to attach to.
    patient_id: Optional[int] = None


_UNKNOWN_VALUES = {"", "unknown", "n/a", "none", "null"}


def _clean_identifier(value) -> Optional[str]:
    value = str(value or "").strip()
    return None if value.lower() in _UNKNOWN_VALUES else value


def _parse_dob(value) -> Optional[datetime.date]:
    raw = _clean_identifier(value)
    if not raw:
        return None
    for fmt in ("%Y-%m-%d", "%d-%m-%Y", "%m/%d/%Y", "%d/%m/%Y", "%Y/%m/%d"):
        try:
            return datetime.datetime.strptime(raw, fmt).date()
        except ValueError:
            continue
    return None


def _resolve_patient(db: Session, name: str, mrn: Optional[str], dob: Optional[datetime.date]):
    """
    Finds (or creates) the Patient this report belongs to, WITHOUT ever
    auto-merging into an existing same-named patient unless a secondary
    identifier (MRN or DOB) confirms it's the same person.

    Returns (patient, ambiguous_candidates). `patient` is None if the match
    is ambiguous - callers must not save anything in that case and should
    surface `ambiguous_candidates` for manual confirmation instead.
    """
    candidates = db.query(models.Patient).filter(models.Patient.name == name).all()
    if not candidates:
        # No name collision at all - safe to create a new patient record.
        patient = models.Patient(name=name, mrn=mrn, dob=dob)
        db.add(patient)
        db.commit()
        db.refresh(patient)
        return patient, []

    if mrn or dob:
        for candidate in candidates:
            if mrn and candidate.mrn and candidate.mrn == mrn:
                return candidate, []
            if dob and candidate.dob and candidate.dob == dob:
                return candidate, []

    # Name matches one or more existing patients, but no MRN/DOB confirms
    # any of them - do not silently attach this report to the wrong person.
    return None, candidates

@router.post("/report")
async def analyze_medical_report(
    patient_name: str | None = Form(None),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """
    Accepts an image of a medical report/lab result/x-ray, uploads to MedGemma for multimodal analysis,
    and returns a structured JSON summary. Does NOT save to DB if patient_name is missing/Unknown.
    """
    try:
        # Nothing here needs the DB until after the LLM call below - release
        # the pooled connection now instead of holding it idle for the
        # duration of the PDF parsing + synchronous LLM call. The session
        # reconnects transparently on its next use (db.query/commit further
        # down).
        db.close()

        if file.content_type not in ALLOWED_UPLOAD_CONTENT_TYPES:
            raise HTTPException(
                status_code=400,
                detail=f"Unsupported file type: {file.content_type}. Allowed types: image/jpeg, image/png, image/webp, application/pdf.",
            )

        content = await file.read()

        if len(content) > MAX_UPLOAD_SIZE_BYTES:
            raise HTTPException(
                status_code=400,
                detail=f"File too large. Maximum allowed size is {MAX_UPLOAD_SIZE_BYTES // (1024 * 1024)}MB.",
            )

        # Convert PDF to image if necessary
        if file.filename and file.filename.lower().endswith(".pdf") or file.content_type == "application/pdf":
            try:
                import fitz
                doc = fitz.open(stream=content, filetype="pdf")
                if len(doc) > 0:
                    page = doc.load_page(0)
                    pix = page.get_pixmap()
                    content = pix.tobytes("jpeg")
                else:
                    raise HTTPException(status_code=400, detail="Empty PDF file.")
            except Exception as e:
                print(f"Failed to parse PDF: {e}")
                raise HTTPException(status_code=400, detail="Invalid PDF file.")

        base64_img = base64.b64encode(content).decode('utf-8')

        prompt = """
        You are an expert medical AI assistant.
        Analyze this medical image (report, lab result, or clinical photo).
        Extract the patient's name if visible. If not clearly visible, return "Unknown".
        Also extract the patient's Medical Record Number (MRN) and date of birth
        (DOB) if either is visible on the document - these are used to confirm
        the patient's identity and avoid confusing two different patients who
        share the same name. If not visible, return "Unknown" for that field.

        Extract the information and return ONLY a valid JSON object with the following schema:
        {
            "patient_name": "extracted name or 'Unknown'",
            "mrn": "extracted medical record number or 'Unknown'",
            "dob": "extracted date of birth (YYYY-MM-DD if possible) or 'Unknown'",
            "key_findings": "A concise summary of the primary findings",
            "abnormalities": "A list or summary of any abnormal values or concerning observations",
            "recommendations": "Suggested next steps or clinical recommendations based on the findings"
        }
        Do not include markdown blocks like ```json. Return raw JSON.
        """

        print(f"Sending image and prompt to MedGemma...")
        # llm_manager.generate_with_image() is a genuinely blocking synchronous
        # call (LLM inference). Run it in a worker thread so it doesn't block
        # the event loop and starve other concurrent requests of DB
        # connections (see /investigate 2026-09-20).
        response_text = await run_in_threadpool(
            llm_manager.generate_with_image, base64_img, prompt, is_clinical=True
        )

        import re
        
        # Try to find the first JSON object block
        json_match = re.search(r'\{.*\}', response_text, re.DOTALL)
        if json_match:
            response_text = json_match.group(0)

        try:
            data = json.loads(response_text)
        except json.JSONDecodeError:
            print(f"JSON Decode Error! Raw LLM Output: {response_text}")
            raise HTTPException(status_code=500, detail="LLM did not return valid JSON.")

        # Determine the effective patient name
        extracted_name = data.get("patient_name", "Unknown").strip()
        final_name = patient_name if patient_name else extracted_name
        
        data["patient_name"] = final_name

        # If name is still Unknown (and user didn't explicitly provide it via Form), require manual confirmation
        if final_name.lower() == "unknown" or final_name == "":
            return {
                "requires_name": True,
                "data": data
            }

        # Otherwise, save automatically - but only once we're sure WHICH
        # patient this is. Name alone is not a safe match: two different
        # patients can share a name, and blindly attaching to an existing
        # same-named row risks merging one patient's report into another
        # patient's record. See _resolve_patient.
        extracted_mrn = _clean_identifier(data.get("mrn"))
        extracted_dob = _parse_dob(data.get("dob"))
        patient, ambiguous_candidates = _resolve_patient(db, final_name, extracted_mrn, extracted_dob)

        if patient is None:
            return {
                "requires_name": False,
                "requires_confirmation": True,
                "reason": (
                    "A patient named '{}' already exists, but no MRN or date "
                    "of birth on this document confirms it's the same person. "
                    "Provide an MRN/DOB, or confirm/select the correct patient "
                    "manually via /api/analysis/save_report."
                ).format(final_name),
                "candidates": [
                    {"id": c.id, "name": c.name, "mrn": c.mrn,
                     "dob": c.dob.isoformat() if c.dob else None}
                    for c in ambiguous_candidates
                ],
                "data": data,
            }

        new_report = models.MedicalReport(
            patient_id=patient.id,
            key_findings=data.get("key_findings", ""),
            abnormalities=data.get("abnormalities", ""),
            recommendations=data.get("recommendations", ""),
            raw_response=response_text
        )
        db.add(new_report)
        db.commit()

        return {
            "requires_name": False,
            "data": {
                "patient_name": final_name,
                "key_findings": new_report.key_findings,
                "abnormalities": new_report.abnormalities,
                "recommendations": new_report.recommendations,
                "date": new_report.date.isoformat() if new_report.date else None
            }
        }

    except HTTPException:
        # Let intentional 4xx responses (e.g. the upload validation above,
        # or the invalid-PDF case) pass through unchanged instead of being
        # swallowed into a generic 500 below.
        raise
    except Exception as e:
        print(f"[Analysis] Error analyzing report: {e}")
        raise HTTPException(status_code=500, detail="Failed to analyze the uploaded report.")

@router.post("/save_report")
async def save_medical_report(
    req: SaveReportRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """
    Saves a report to the database after manual confirmation of the patient name.
    """
    try:
        final_name = req.patient_name.strip()
        if not final_name or final_name.lower() == "unknown":
            raise HTTPException(status_code=400, detail="Invalid patient name.")

        if req.patient_id is not None:
            # Caller (e.g. an admin resolving an earlier ambiguous-match
            # response) has explicitly picked the patient - trust that
            # over any name/MRN/DOB heuristic.
            patient = db.query(models.Patient).filter(models.Patient.id == req.patient_id).first()
            if not patient:
                raise HTTPException(status_code=404, detail="Selected patient not found.")
        else:
            extracted_mrn = _clean_identifier(req.mrn)
            extracted_dob = _parse_dob(req.dob)
            patient, ambiguous_candidates = _resolve_patient(db, final_name, extracted_mrn, extracted_dob)
            if patient is None:
                raise HTTPException(
                    status_code=409,
                    detail={
                        "requires_confirmation": True,
                        "reason": (
                            f"A patient named '{final_name}' already exists, but no MRN "
                            "or date of birth confirms it's the same person. Provide an "
                            "MRN/DOB, or resubmit with an explicit patient_id."
                        ),
                        "candidates": [
                            {"id": c.id, "name": c.name, "mrn": c.mrn,
                             "dob": c.dob.isoformat() if c.dob else None}
                            for c in ambiguous_candidates
                        ],
                    },
                )

        new_report = models.MedicalReport(
            patient_id=patient.id,
            key_findings=req.key_findings,
            abnormalities=req.abnormalities,
            recommendations=req.recommendations,
            raw_response=json.dumps(req.dict())
        )
        db.add(new_report)
        db.commit()

        return {
            "success": True,
            "patient_name": final_name,
            "key_findings": new_report.key_findings,
            "abnormalities": new_report.abnormalities,
            "recommendations": new_report.recommendations,
            "date": new_report.date.isoformat() if new_report.date else None
        }
    except HTTPException:
        # Let intentional 4xx/409 responses (invalid name, unresolved
        # patient match, etc.) pass through unchanged instead of being
        # swallowed into a generic 500 below.
        raise
    except Exception as e:
        print(f"[Analysis] Error saving report: {e}")
        raise HTTPException(status_code=500, detail="Failed to save the report.")
