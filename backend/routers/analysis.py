from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session
import json
import base64
import os

from database import get_db
from routers.auth import get_current_user
import models
from services.llm_manager import llm_manager

router = APIRouter(prefix="/api/analysis", tags=["analysis"])

class SaveReportRequest(BaseModel):
    patient_name: str
    key_findings: str
    abnormalities: str
    recommendations: str

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
        content = await file.read()
        base64_img = base64.b64encode(content).decode('utf-8')

        prompt = """
        You are an expert medical AI assistant.
        Analyze this medical image (report, lab result, or clinical photo).
        Extract the patient's name if visible. If not clearly visible, return "Unknown".
        
        Extract the information and return ONLY a valid JSON object with the following schema:
        {
            "patient_name": "extracted name or 'Unknown'",
            "key_findings": "A concise summary of the primary findings",
            "abnormalities": "A list or summary of any abnormal values or concerning observations",
            "recommendations": "Suggested next steps or clinical recommendations based on the findings"
        }
        Do not include markdown blocks like ```json. Return raw JSON.
        """

        print(f"Sending image and prompt to MedGemma...")
        response_text = llm_manager.generate_with_image(base64_img, prompt, is_clinical=True)

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

        # Otherwise, save automatically!
        patient = db.query(models.Patient).filter(models.Patient.name == final_name).first()
        if not patient:
            patient = models.Patient(name=final_name)
            db.add(patient)
            db.commit()
            db.refresh(patient)

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

    except Exception as e:
        print(f"Error analyzing report: {e}")
        raise HTTPException(status_code=500, detail=str(e))

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

        patient = db.query(models.Patient).filter(models.Patient.name == final_name).first()
        if not patient:
            patient = models.Patient(name=final_name)
            db.add(patient)
            db.commit()
            db.refresh(patient)

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
    except Exception as e:
        print(f"Error saving report: {e}")
        raise HTTPException(status_code=500, detail=str(e))
