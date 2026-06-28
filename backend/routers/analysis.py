from fastapi import APIRouter, Depends, UploadFile, File, Form, HTTPException
from sqlalchemy.orm import Session
from google import genai
from google.genai import types
import json
import os
import tempfile

from database import get_db
from routers.auth import get_current_user
import models

router = APIRouter(prefix="/api/analysis", tags=["analysis"])

GENAI_API_KEY = os.getenv("GEMINI_API_KEY")
client = genai.Client(api_key=GENAI_API_KEY)

@router.post("/report")
async def analyze_medical_report(
    patient_name: str = Form(...),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """
    Accepts an image of a medical report/lab result/x-ray, uploads to Gemini for multimodal analysis,
    and returns a structured JSON summary.
    """
    if not GENAI_API_KEY:
        raise HTTPException(status_code=500, detail="Gemini API Key not configured")

    try:
        # Save uploaded file temporarily
        suffix = os.path.splitext(file.filename)[1] or '.jpg'
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp:
            content = await file.read()
            temp.write(content)
            temp_path = temp.name

        # Upload to Gemini File API
        print(f"Uploading {temp_path} to Gemini...")
        gemini_file = client.files.upload(file=temp_path)

        # Prompt for structured extraction
        prompt = f"""
        You are an expert medical AI assistant.
        Analyze the attached medical image (report, lab result, or clinical photo) for patient '{patient_name}'.
        Extract the information and return ONLY a valid JSON object with the following schema:
        {{
            "key_findings": "A concise summary of the primary findings",
            "abnormalities": "A list or summary of any abnormal values or concerning observations",
            "recommendations": "Suggested next steps or clinical recommendations based on the findings"
        }}
        Do not include markdown blocks like ```json. Return raw JSON.
        """

        response = client.models.generate_content(
            model='gemini-2.5-flash',
            contents=[gemini_file, prompt],
            config=types.GenerateContentConfig(
                temperature=0.2, # Low temp for medical extraction
            )
        )

        response_text = response.text.strip()
        if response_text.startswith("```json"):
            response_text = response_text[7:-3].strip()
        elif response_text.startswith("```"):
            response_text = response_text[3:-3].strip()

        data = json.loads(response_text)

        # Get or create patient
        patient = db.query(models.Patient).filter(models.Patient.name == patient_name).first()
        if not patient:
            patient = models.Patient(name=patient_name)
            db.add(patient)
            db.commit()
            db.refresh(patient)

        # Save to DB
        new_report = models.MedicalReport(
            patient_id=patient.id,
            key_findings=data.get("key_findings", ""),
            abnormalities=data.get("abnormalities", ""),
            recommendations=data.get("recommendations", ""),
            raw_response=response_text
        )
        db.add(new_report)
        db.commit()

        # Clean up
        os.remove(temp_path)
        client.files.delete(name=gemini_file.name)

        return {
            "patient_name": patient_name,
            "key_findings": new_report.key_findings,
            "abnormalities": new_report.abnormalities,
            "recommendations": new_report.recommendations,
            "date": new_report.date.isoformat() if new_report.date else None
        }

    except Exception as e:
        print(f"Error analyzing report: {e}")
        raise HTTPException(status_code=500, detail=str(e))
