"""
First-run setup for a fresh hospital deployment.

Replaces two prior gaps:
  - POST /api/auth/setup-admin (routers/auth.py) auto-created "admin"/"admin"
    with superadmin role the instant anyone opened the login page, with no
    hospital input and no way to choose real credentials.
  - seed_hospital_roles.py / seed_rbac.py were meant to be hand-run once by
    an engineer, hardcoding six demo accounts where the password equals the
    username (admin/admin, superadmin/superadmin, etc.) — a serious risk if
    ever run against a real client database instead of local dev.

This router is intentionally NOT behind auth (there's no user yet on a fresh
deployment), but /initialize is a one-shot: once any user exists, it refuses.
"""
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, field_validator
from sqlalchemy.orm import Session

import models
from database import get_db
from routers.auth import get_password_hash

router = APIRouter(prefix="/api/setup", tags=["setup"])

# Same permission set seed_hospital_roles.py defined, minus the six demo
# accounts it also used to create.
_DEFAULT_PERMISSIONS = {
    "view_admin": "Access to Super Admin Dashboard",
    "view_consultation": "Access to Consultation Screen",
    "view_camera": "Access to AI Camera Screen",
    "view_analytics": "Access to Analytics Dashboard",
    "view_security": "Access to Security Dashboard",
    "view_agent": "Access to Medical Agent",
    "view_settings": "Access to System Settings",
    "view_indoor_tracking": "View live indoor location tracking on the hospital map",
    "manage_indoor_tracking": "Configure hospital floors, rooms, Wi-Fi APs and geofence for indoor tracking",
    # Gates /directory (app_router.dart) - the People Directory used to find
    # and call/message other staff. Added along with the Directory screen,
    # but never actually added here, so /directory silently redirected away
    # for every single account, including SuperAdmin - the calling feature
    # had no reachable entry point in the UI at all (/investigate 2026-09-17).
    "view_patients": "Access to the People Directory (patients, doctors, staff)",
    # Gates create/delete/sync of security.py's SecurityRule endpoints, which
    # previously had no auth dependency at all - any unauthenticated caller
    # could wipe or rewrite every rule via /rules/sync (/investigate 2026-09-20).
    "manage_security": "Configure and sync security alert rules",
}

_DEFAULT_ROLES = {
    # Indoor Tracking is admin-only by design (per user 2026-09-19) -
    # Doctor/Nurse deliberately do NOT get view_indoor_tracking. Security
    # keeps it since patrol/response is its actual job.
    "Doctor": ["view_consultation", "view_agent", "view_patients"],
    "Nurse": ["view_consultation", "view_agent", "view_patients"],
    "Security": ["view_camera", "view_security", "view_indoor_tracking", "view_patients", "manage_security"],
    "Analyst": ["view_analytics", "view_patients"],
    "Admin": ["view_settings", "view_camera", "view_patients", "manage_security"],
    "SuperAdmin": list(_DEFAULT_PERMISSIONS.keys()),
}


class SetupStatusResponse(BaseModel):
    initialized: bool


class SetupInitializeRequest(BaseModel):
    hospital_name: str
    agent_name: str = "AI"
    admin_username: str
    admin_password: str

    @field_validator("hospital_name", "admin_username")
    @classmethod
    def _not_blank(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("must not be blank")
        return v

    @field_validator("admin_password")
    @classmethod
    def _password_strength(cls, v: str) -> str:
        # Deliberately not fancy (no special-char rules) — just rules out
        # the exact failure mode this replaces: a password equal to a
        # well-known default.
        if len(v) < 8:
            raise ValueError("password must be at least 8 characters")
        if v.lower() in ("admin", "password", "12345678", "superadmin"):
            raise ValueError("password is too common — choose something harder to guess")
        return v


class SetupInitializeResponse(BaseModel):
    hospital_name: str
    admin_username: str


@router.get("/status", response_model=SetupStatusResponse)
def get_setup_status(db: Session = Depends(get_db)):
    """Public — the Flutter app checks this before showing login vs. the setup wizard."""
    initialized = db.query(models.User).first() is not None
    return SetupStatusResponse(initialized=initialized)


@router.post("/initialize", response_model=SetupInitializeResponse)
def initialize_deployment(
    body: SetupInitializeRequest, db: Session = Depends(get_db)
):
    """
    One-shot. Refuses once any user already exists, so this can't be replayed
    to create a second superadmin or reset an already-configured deployment.
    """
    if db.query(models.User).first() is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This deployment has already been initialized.",
        )

    # Hospital branding (site_config.py owns this table normally; setup just
    # populates the same singleton row so branding is correct from the start).
    config = db.query(models.SiteConfig).filter(models.SiteConfig.id == 1).first()
    if config is None:
        config = models.SiteConfig(id=1)
        db.add(config)
    config.hospital_name = body.hospital_name
    config.agent_name = body.agent_name

    # Permissions + roles (same shape as seed_hospital_roles.py, no demo users).
    db_perms: dict[str, models.RBACPermission] = {}
    for name, description in _DEFAULT_PERMISSIONS.items():
        perm = db.query(models.RBACPermission).filter(
            models.RBACPermission.name == name
        ).first()
        if perm is None:
            perm = models.RBACPermission(name=name, description=description)
            db.add(perm)
            db.flush()
        db_perms[name] = perm

    superadmin_group: Optional[models.RBACGroup] = None
    for role_name, perm_names in _DEFAULT_ROLES.items():
        group = db.query(models.RBACGroup).filter(
            models.RBACGroup.name == role_name
        ).first()
        if group is None:
            group = models.RBACGroup(name=role_name, description=f"{role_name} Role")
            db.add(group)
            db.flush()
        for perm_name in perm_names:
            perm = db_perms[perm_name]
            if perm not in group.permissions:
                group.permissions.append(perm)
        if role_name == "SuperAdmin":
            superadmin_group = group

    # The one real admin account, with the credentials THEY chose.
    admin_user = models.User(
        username=body.admin_username,
        hashed_password=get_password_hash(body.admin_password),
        role="superadmin",
    )
    db.add(admin_user)
    db.flush()
    if superadmin_group is not None:
        admin_user.groups.append(superadmin_group)

    db.commit()

    return SetupInitializeResponse(
        hospital_name=config.hospital_name, admin_username=admin_user.username
    )
