import os
import shutil
from typing import Optional

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from pydantic import BaseModel
from sqlalchemy.orm import Session

import models
from database import get_db
from routers.auth import get_current_user

router = APIRouter(prefix="/api/site-config", tags=["site-config"])


class SiteConfigResponse(BaseModel):
    hospital_name: str
    agent_name: str
    logo_url: Optional[str] = None


class SiteConfigUpdate(BaseModel):
    hospital_name: Optional[str] = None
    agent_name: Optional[str] = None


def _get_or_create_config(db: Session) -> models.SiteConfig:
    """Return the singleton SiteConfig row, creating it if absent."""
    config = db.query(models.SiteConfig).filter(models.SiteConfig.id == 1).first()
    if config is None:
        config = models.SiteConfig(id=1)
        db.add(config)
        db.commit()
        db.refresh(config)
    return config


def _logo_url(config: models.SiteConfig) -> Optional[str]:
    if config.logo_path:
        return f"/uploads/{config.logo_path}"
    return None


@router.get("", response_model=SiteConfigResponse)
def get_site_config(db: Session = Depends(get_db)):
    """Public endpoint — anyone can read branding."""
    config = _get_or_create_config(db)
    return SiteConfigResponse(
        hospital_name=config.hospital_name,
        agent_name=config.agent_name,
        logo_url=_logo_url(config),
    )


@router.put("", response_model=SiteConfigResponse)
def update_site_config(
    body: SiteConfigUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Superadmin-only: update hospital name / agent name."""
    if current_user.role != "superadmin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only superadmin can update site configuration.",
        )

    config = _get_or_create_config(db)
    if body.hospital_name is not None:
        config.hospital_name = body.hospital_name
    if body.agent_name is not None:
        config.agent_name = body.agent_name
    db.commit()
    db.refresh(config)

    return SiteConfigResponse(
        hospital_name=config.hospital_name,
        agent_name=config.agent_name,
        logo_url=_logo_url(config),
    )


@router.post("/logo", response_model=SiteConfigResponse)
async def upload_logo(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Superadmin-only: upload a hospital logo image."""
    if current_user.role != "superadmin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only superadmin can upload the hospital logo.",
        )

    allowed_ext = {"png", "jpg", "jpeg", "svg", "webp"}
    ext = (file.filename or "logo.png").rsplit(".", 1)[-1].lower()
    if ext not in allowed_ext:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid file type. Allowed: {', '.join(allowed_ext)}",
        )

    logo_dir = os.path.join("uploads", "branding")
    os.makedirs(logo_dir, exist_ok=True)

    filename = f"hospital_logo.{ext}"
    filepath = os.path.join(logo_dir, filename)

    # Remove old logos
    for old_file in os.listdir(logo_dir):
        if old_file.startswith("hospital_logo"):
            os.remove(os.path.join(logo_dir, old_file))

    with open(filepath, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    config = _get_or_create_config(db)
    config.logo_path = f"branding/{filename}"
    db.commit()
    db.refresh(config)

    return SiteConfigResponse(
        hospital_name=config.hospital_name,
        agent_name=config.agent_name,
        logo_url=_logo_url(config),
    )


@router.delete("/logo", response_model=SiteConfigResponse)
def delete_logo(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """Superadmin-only: remove the hospital logo."""
    if current_user.role != "superadmin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only superadmin can delete the hospital logo.",
        )

    config = _get_or_create_config(db)
    if config.logo_path:
        full_path = os.path.join("uploads", config.logo_path)
        if os.path.exists(full_path):
            os.remove(full_path)
        config.logo_path = None
        db.commit()
        db.refresh(config)

    return SiteConfigResponse(
        hospital_name=config.hospital_name,
        agent_name=config.agent_name,
        logo_url=None,
    )
