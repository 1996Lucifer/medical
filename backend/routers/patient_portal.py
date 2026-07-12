from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException
from sqlalchemy.orm import Session
from typing import List, Optional
from pydantic import BaseModel
import os
import base64
import json
import datetime
import fitz  # PyMuPDF
import io
from PIL import Image

from database import get_db
import models
from services.llm_manager import llm_manager

router = APIRouter(prefix="/api/patient-portal", tags=["patient-portal"])

# Ensure upload dir exists
UPLOAD_DIR = os.path.join(os.path.dirname(__file__), "..", "uploads", "reports")
os.makedirs(UPLOAD_DIR, exist_ok=True)


class ReportResponse(BaseModel):
    id: int
    date: datetime.datetime
    file_path: Optional[str]
    key_findings: Optional[str]
    abnormalities: Optional[str]
    recommendations: Optional[str]
    vitals_extracted: Optional[str]
    
    class Config:
        from_attributes = True

class ConsultationResponse(BaseModel):
    id: int
    date: datetime.datetime
    transcript: Optional[str]
    discharge_summary: Optional[str]
    prescription: Optional[str]
    
    class Config:
        from_attributes = True


@router.post("/reports/upload", response_model=ReportResponse)
async def upload_report(
    patient_id: int = Form(...),
    file: UploadFile = File(...),
    db: Session = Depends(get_db)
):
    """
    Uploads a medical report (Image or PDF).
    Uses PyMuPDF to convert PDF to Image if needed.
    Passes the image to MedGemma to extract findings and structured vitals.
    """
    patient = db.query(models.Patient).filter(models.Patient.id == patient_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")

    file_extension = os.path.splitext(file.filename)[1].lower()
    timestamp = datetime.datetime.now().strftime("%Y%m%d%H%M%S")
    safe_filename = f"report_{patient_id}_{timestamp}{file_extension}"
    file_path = os.path.join(UPLOAD_DIR, safe_filename)

    content = await file.read()
    with open(file_path, "wb") as f:
        f.write(content)

    base64_img = ""
    if file_extension == ".pdf":
        # Convert first page of PDF to image for MedGemma
        try:
            pdf_document = fitz.open(stream=content, filetype="pdf")
            if len(pdf_document) > 0:
                page = pdf_document.load_page(0)
                pix = page.get_pixmap()
                img = Image.frombytes("RGB", [pix.width, pix.height], pix.samples)
                buffered = io.BytesIO()
                img.save(buffered, format="JPEG")
                base64_img = base64.b64encode(buffered.getvalue()).decode("utf-8")
            pdf_document.close()
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to process PDF: {str(e)}")
    else:
        # Standard image (jpg, png)
        base64_img = base64.b64encode(content).decode("utf-8")

    if not base64_img:
        raise HTTPException(status_code=400, detail="Could not process file to image")

    # Prompt MedGemma for extraction
    prompt = (
        "Analyze this medical report. Extract the following information and format it STRICTLY as a JSON object: "
        '{"key_findings": "Summary of main findings", "abnormalities": "Any abnormal results", '
        '"recommendations": "Any recommendations made", '
        '"vitals": {"heart_rate": 80, "blood_pressure": "120/80", "blood_sugar": 100} '
        "(Only include vitals if they are present in the document, otherwise empty object)}."
    )

    raw_response = llm_manager.generate_with_image(base64_img, prompt, is_clinical=True)
    
    # Simple JSON extraction (strip markdown code blocks if any)
    json_str = raw_response
    if "```json" in json_str:
        json_str = json_str.split("```json")[1].split("```")[0].strip()
    elif "```" in json_str:
        json_str = json_str.split("```")[1].split("```")[0].strip()

    try:
        extracted_data = json.loads(json_str)
        key_findings = extracted_data.get("key_findings")
        abnormalities = extracted_data.get("abnormalities")
        recommendations = extracted_data.get("recommendations")
        vitals = json.dumps(extracted_data.get("vitals", {}))
    except json.JSONDecodeError:
        # Fallback if AI didn't return valid JSON
        key_findings = raw_response
        abnormalities = None
        recommendations = None
        vitals = "{}"

    new_report = models.MedicalReport(
        patient_id=patient_id,
        file_path=file_path,
        key_findings=key_findings,
        abnormalities=abnormalities,
        recommendations=recommendations,
        vitals_extracted=vitals,
        raw_response=raw_response
    )
    
    db.add(new_report)
    db.commit()
    db.refresh(new_report)

    return new_report

@router.get("/reports/{patient_id}", response_model=List[ReportResponse])
def get_reports(patient_id: int, db: Session = Depends(get_db)):
    reports = db.query(models.MedicalReport).filter(models.MedicalReport.patient_id == patient_id).order_by(models.MedicalReport.date.desc()).all()
    return reports

@router.get("/consultations/{patient_id}", response_model=List[ConsultationResponse])
def get_consultations(patient_id: int, db: Session = Depends(get_db)):
    consultations = db.query(models.Consultation).filter(models.Consultation.patient_id == patient_id).order_by(models.Consultation.date.desc()).all()
    return consultations

@router.get("/dashboard/{patient_id}")
def get_dashboard_data(patient_id: int, db: Session = Depends(get_db)):
    """
    Returns aggregated data for the charts (e.g., historical vitals from reports)
    """
    reports = db.query(models.MedicalReport).filter(
        models.MedicalReport.patient_id == patient_id,
        models.MedicalReport.vitals_extracted != None
    ).order_by(models.MedicalReport.date.asc()).all()

    chart_data = []
    for report in reports:
        try:
            vitals = json.loads(report.vitals_extracted)
            if vitals:
                chart_data.append({
                    "date": report.date.isoformat(),
                    "vitals": vitals
                })
        except:
            pass

    return {"chart_data": chart_data}
