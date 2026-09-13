from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from pydantic import BaseModel
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
import bcrypt
import jwt
import os
import threading
import time

from database import get_db
import models

router = APIRouter(prefix="/api/auth", tags=["auth"])

# Previously defaulted to a hardcoded string ("super_secret_hospital_key_
# please_change") when SECRET_KEY wasn't set — since that string is sitting
# in this file's source, anyone who has ever seen the codebase could forge a
# valid JWT for any user (including superadmin) on any deployment that
# forgot to set the env var. .env.example didn't even document it, making
# that easy to forget. Now failing loudly instead: a missing secret is a
# startup error, not a silent security hole. Set ALLOW_INSECURE_DEFAULT_SECRET=1
# only for a disposable local sandbox — never in anything reachable by
# real patient data.
SECRET_KEY = os.getenv("SECRET_KEY")
if not SECRET_KEY:
    if os.getenv("ALLOW_INSECURE_DEFAULT_SECRET") == "1":
        SECRET_KEY = "super_secret_hospital_key_please_change"
        print(
            "[auth] WARNING: SECRET_KEY not set — using the insecure default "
            "because ALLOW_INSECURE_DEFAULT_SECRET=1. Do not do this outside "
            "a disposable local sandbox."
        )
    else:
        raise RuntimeError(
            "SECRET_KEY environment variable is not set. Generate one with "
            "`python3 -c \"import secrets; print(secrets.token_hex(32))\"` "
            "and add it to your .env file. (Set ALLOW_INSECURE_DEFAULT_SECRET=1 "
            "instead only for a throwaway local sandbox with no real data.)"
        )
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7 # 1 week

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login")

# ── Login rate limiting ─────────────────────────────────────────────────────
# There was previously NO throttling at all on /login — unlimited attempts
# per second, no lockout. Harmless while the only credential was the known
# "admin"/"admin" default; a real problem now that a real admin password is
# the only thing standing between an attacker and superadmin. In-memory and
# per-process: fine for the current single-process deployment, but won't be
# shared across workers if this ever runs with `uvicorn --workers N` — that
# would need a shared store (Redis, already proposed for the scaling piece)
# instead of this dict.
_LOGIN_MAX_ATTEMPTS = 5
_LOGIN_WINDOW_SEC = 15 * 60
_LOGIN_LOCKOUT_SEC = 15 * 60

_login_failures_lock = threading.Lock()
_login_failures: dict[str, list[float]] = {}


def _is_locked_out(username: str) -> bool:
    key = username.strip().lower()
    now = time.monotonic()
    with _login_failures_lock:
        attempts = _login_failures.get(key, [])
        attempts = [t for t in attempts if now - t < _LOGIN_WINDOW_SEC]
        _login_failures[key] = attempts
        if len(attempts) < _LOGIN_MAX_ATTEMPTS:
            return False
        # Locked out while the most recent failure is within the lockout
        # window; once it ages out, the streak is forgotten and attempts
        # start counting again from zero.
        return (now - attempts[-1]) < _LOGIN_LOCKOUT_SEC


def _record_login_failure(username: str) -> None:
    key = username.strip().lower()
    with _login_failures_lock:
        _login_failures.setdefault(key, []).append(time.monotonic())


def _clear_login_failures(username: str) -> None:
    key = username.strip().lower()
    with _login_failures_lock:
        _login_failures.pop(key, None)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    password_bytes = plain_password.encode('utf-8')
    hashed_bytes = hashed_password.encode('utf-8')
    try:
        return bcrypt.checkpw(password_bytes, hashed_bytes)
    except ValueError:
        return False

def get_password_hash(password: str) -> str:
    password_bytes = password.encode('utf-8')
    hashed_bytes = bcrypt.hashpw(password_bytes, bcrypt.gensalt())
    return hashed_bytes.decode('utf-8')

def create_access_token(data: dict, expires_delta: timedelta = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=15)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            raise credentials_exception
    except jwt.PyJWTError:
        raise credentials_exception

    user = db.query(models.User).filter(models.User.username == username).first()
    if user is None:
        raise credentials_exception
    return user

@router.post("/login")
def login_for_access_token(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    if _is_locked_out(form_data.username):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=(
                f"Too many failed login attempts. Try again in "
                f"{_LOGIN_LOCKOUT_SEC // 60} minutes."
            ),
        )

    user = db.query(models.User).filter(models.User.username == form_data.username).first()
    if not user or not verify_password(form_data.password, user.hashed_password):
        _record_login_failure(form_data.username)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    _clear_login_failures(form_data.username)

    # Only "active" and "change_password" may actually sign in — anything
    # else (currently just "inactive"; "pending" reserved for later) is a
    # revoked/disabled account. Checked after password verification so a
    # bad guess against a revoked username still gets the generic
    # "incorrect username or password", not a hint that the account exists.
    if user.status not in ("active", "change_password"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access Denied. Contact admin.",
        )

    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": user.username, "role": user.role}, expires_delta=access_token_expires
    )
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "username": user.username,
        "role": user.role,
        "must_change_password": user.status == "change_password",
    }

def has_permission(user: models.User, permission_name: str) -> bool:
    """Superadmin bypasses all checks. Otherwise checks direct grants and group grants."""
    if user.role == "superadmin":
        return True
    for p in user.direct_permissions:
        if p.name == permission_name:
            return True
    for g in user.groups:
        for p in g.permissions:
            if p.name == permission_name:
                return True
    return False


def require_permission(permission_name: str):
    """Dependency factory: 403s unless the current user holds permission_name (or is superadmin)."""

    def _check(current_user: models.User = Depends(get_current_user)):
        if not has_permission(current_user, permission_name):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Missing required permission: {permission_name}",
            )
        return current_user

    return _check


@router.get("/me")
def get_current_user_info(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    permissions = set()
    for p in current_user.direct_permissions:
        permissions.add(p.name)
    for g in current_user.groups:
        for p in g.permissions:
            permissions.add(p.name)

    # Lets the frontend know "which patient/staff record am I" - needed for
    # the patient portal (my own patient_id) and doctor-side calling/patient
    # list (my own staff_id) without a separate lookup round-trip.
    patient = db.query(models.Patient).filter(models.Patient.user_id == current_user.id).first()
    staff = db.query(models.Staff).filter(models.Staff.user_id == current_user.id).first()

    return {
        "id": current_user.id,
        "username": current_user.username,
        "role": current_user.role,
        "permissions": list(permissions),
        "must_change_password": current_user.status == "change_password",
        "patient_id": patient.id if patient else None,
        "staff_id": staff.id if staff else None,
        "staff_category": staff.category if staff else None,
    }


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str


@router.post("/change-password")
def change_password(
    body: ChangePasswordRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not verify_password(body.current_password, current_user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Current password is incorrect",
        )

    if len(body.new_password) < 8:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="New password must be at least 8 characters",
        )
    weak = {"admin", "password", "12345678", "superadmin"}
    if body.new_password.lower() in weak:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Choose a less predictable password",
        )

    current_user.hashed_password = get_password_hash(body.new_password)
    if current_user.status == "change_password":
        current_user.status = "active"
    db.commit()
    return {"status": "success"}
