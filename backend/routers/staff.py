import os
import shutil
import datetime
import uuid
import cv2
import numpy as np
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, WebSocket, WebSocketDisconnect, Query
from fastapi.concurrency import run_in_threadpool
from sqlalchemy.orm import Session
from sqlalchemy import func
from pydantic import BaseModel, ConfigDict

from database import get_db
import models
from camera.vision_service import vision_service
from services.auth_provisioning import create_login_account
from services.staff.hierarchy import can_assign, effective_head, would_create_cycle
from routers.auth import get_current_user, require_permission

router = APIRouter(prefix="/api/staff", tags=["staff"])
ws_router = APIRouter(prefix="/api/staff", tags=["staff_ws"])

# Pagination defaults for list endpoints (see get_staff below) - a sensible
# default page size plus a hard cap so a client can't force an unbounded
# query by passing an absurd limit.
DEFAULT_PAGE_SIZE = 50
MAX_PAGE_SIZE = 200


def _create_login_for_staff(db: Session, name: str, role: Optional[str], commit: bool = True):
    """
    Create a login account alongside a new Staff (biometric) record - see
    services/auth_provisioning.create_login_account for the shared
    implementation (also used for patient portal accounts).
    """
    return create_login_account(db, name, role or "Medical Staff", fallback_username="staff", commit=commit)


class StaffResponse(BaseModel):
    id: int
    name: str
    role: Optional[str] = "Medical Staff"
    category: Optional[str] = "Medical Staff"
    photo_count: int = 0
    photo_url: Optional[str] = None
    # The linked login account's lifecycle status ("active",
    # "change_password", "inactive", ...) — None if this staff member has
    # no linked account (registered before this existed).
    status: Optional[str] = None
    # user_id/can_call let the People Directory grid show a working call
    # button for this staff member (see services/calls/authorization.py -
    # any staff/admin account may call any other staff/admin account).
    user_id: Optional[int] = None
    can_call: bool = False
    # Only populated on the creation response — a one-time temporary
    # credential the admin must relay to the new hire. Never re-sent by
    # any other endpoint (the plaintext isn't stored anywhere).
    username: Optional[str] = None
    temp_password: Optional[str] = None
    # "HH:MM" strings, or null if this staff member has no fixed shift
    # configured (e.g. Admin/SuperAdmin roles) - see models.Staff.
    shift_start: Optional[str] = None
    shift_end: Optional[str] = None
    expected_shift_hours: Optional[float] = None
    # Reporting hierarchy - see services/staff/hierarchy.py. reports_to_id/
    # name reflect the RESOLVED effective head (explicit assignment, else
    # department/category head), not just the raw column, so the UI never
    # has to re-derive the fallback chain itself.
    is_head: bool = False
    department: Optional[str] = None
    reports_to_id: Optional[int] = None
    reports_to_name: Optional[str] = None
    model_config = ConfigDict(from_attributes=True)

class StaffActivityResponse(BaseModel):
    id: int
    title: str
    subtitle: str
    color: str
    created_at: datetime.datetime
    model_config = ConfigDict(from_attributes=True)

def _log_activity(db: Session, title: str, subtitle: str, color: str):
    db_activity = models.StaffActivity(title=title, subtitle=subtitle, color=color)
    db.add(db_activity)
    db.commit()


class StaffPhotoResponse(BaseModel):
    id: int
    staff_id: int
    label: Optional[str]
    photo_url: Optional[str] = None
    created_at: datetime.datetime
    model_config = ConfigDict(from_attributes=True)


def _time_to_hhmm(t: Optional[datetime.time]) -> Optional[str]:
    return t.strftime("%H:%M") if t else None


def _hhmm_to_time(s: Optional[str]) -> Optional[datetime.time]:
    return datetime.datetime.strptime(s, "%H:%M").time() if s else None


class StaffUpdate(BaseModel):
    name: str
    role: Optional[str] = "Medical Staff"
    category: Optional[str] = "Medical Staff"
    # "HH:MM", or null for no fixed shift - always sent as the full current
    # state by the Edit Profile dialog, so null unambiguously means "clear".
    shift_start: Optional[str] = None
    shift_end: Optional[str] = None
    # is_head is an elevation of authority (see models.Staff), so it's only
    # ever changed through this manage_staff-gated endpoint, never through
    # the head-only PUT /{staff_id}/assignment below. department/
    # reports_to_id ARE also editable here so an admin retains the same
    # unconditional override that manage_staff already has everywhere
    # else - the assignment endpoint exists to let a HEAD do this too,
    # without needing full manage_staff.
    is_head: bool = False
    department: Optional[str] = None
    reports_to_id: Optional[int] = None


class StaffAssignmentUpdate(BaseModel):
    """
    Body for PUT /{staff_id}/assignment - deliberately narrower than
    StaffUpdate above (name/role/category/shift/is_head are absent): this
    endpoint exists specifically so a head can (re)assign their own
    reports without needing the broader manage_staff permission that
    those other fields require.
    """
    department: Optional[str] = None
    reports_to_id: Optional[int] = None


def _average_normalized(vectors: list) -> Optional[np.ndarray]:
    """L2-normalize each vector, average them, then re-normalize the mean.
    Standard multi-shot-enrollment aggregation: averages out per-photo noise
    (pose/lighting) without letting any single photo's raw scale dominate."""
    if not vectors:
        return None
    normed = []
    for v in vectors:
        arr = np.asarray(v, dtype=np.float32)
        n = np.linalg.norm(arr)
        normed.append(arr / n if n > 0 else arr)
    avg = np.mean(normed, axis=0)
    avg_norm = np.linalg.norm(avg)
    return avg / avg_norm if avg_norm > 0 else avg


def load_staff_list(db: Session) -> list:
    """
    Build the face-recognition gallery: ONE canonical embedding per staff
    member, averaged across every enrolled photo (primary + all additional
    StaffPhoto rows).

    IMPORTANT: this must emit exactly one gallery row per staff member, not
    one row per enrollment photo. A live-recognition match is decided by
    the single highest-scoring gallery row (np.argmax over the whole
    matrix) - with N raw photo-rows per person, matching becomes "does ANY
    of N rows score high" instead of "does this ONE person score high",
    and the max of more attempts drifts upward from pure chance even if no
    single photo's match quality changed. Found via /investigate
    2026-09-14: two different real people were both scoring 65-66% against
    one identity that had 5 separate enrollment-photo rows in the gallery -
    collapsing to one averaged row per identity removes that inflation.
    """
    staff_records = db.query(models.Staff).all()
    staff_list = []
    for s in staff_records:
        embeddings = [s.embedding] if s.embedding is not None else []
        upper_embeddings = [s.upper_embedding] if s.upper_embedding is not None else []
        for photo in s.photos:
            if photo.embedding is not None:
                embeddings.append(photo.embedding)
            if photo.upper_embedding is not None:
                upper_embeddings.append(photo.upper_embedding)

        avg_embedding = _average_normalized(embeddings)
        if avg_embedding is None:
            continue  # no enrolled photo at all - nothing to add to the gallery

        entry = {"id": s.id, "name": s.name, "embedding": avg_embedding.tolist()}
        avg_upper = _average_normalized(upper_embeddings)
        if avg_upper is not None:
            entry["upper_embedding"] = avg_upper.tolist()
        staff_list.append(entry)
    return staff_list

def update_global_embeddings(db: Session):
    staff_list = load_staff_list(db)
    # The multi-camera zone service runs in a separate process, so it needs
    # the refreshed identity set without waiting for a camera restart.
    from camera.vision_worker import vision_process_manager
    vision_process_manager.update_staff(staff_list)


@router.post("", response_model=StaffResponse)
async def register_staff(
    name: str,
    role: Optional[str] = "Medical Staff",
    category: Optional[str] = "Medical Staff",
    file: Optional[UploadFile] = None,
    db: Session = Depends(get_db),
    _admin: models.User = Depends(require_permission("manage_staff")),
):
    """Register a new staff member with an optional first face photo."""
    db_staff = models.Staff(name=name, role=role, category=category)
    filename = None
    
    if file is not None:
        upload_dir = "uploads/staff"
        os.makedirs(upload_dir, exist_ok=True)
        
        filename = f"{uuid.uuid4().hex}_{file.filename}"
        file_path = os.path.join(upload_dir, filename)
        
        try:
            with open(file_path, "wb") as buffer:
                shutil.copyfileobj(file.file, buffer)

            embedding = vision_service.extract_embedding(file_path)
            upper_embedding = vision_service.extract_upper_embedding(image_path=file_path)
            if embedding is None:
                if os.path.exists(file_path):
                    os.remove(file_path)
                raise HTTPException(status_code=400, detail="No face detected in the image.")

            db_staff.embedding = embedding.tolist()
            if upper_embedding is not None:
                db_staff.upper_embedding = upper_embedding.tolist()
            db_staff.photo_path = file_path
        except Exception as e:
            if os.path.exists(file_path):
                os.remove(file_path)
            import traceback
            traceback.print_exc()
            print(f"[Staff] Error registering staff photo: {e}")
            raise HTTPException(status_code=500, detail="Failed to process staff photo.")

    db.add(db_staff)

    # Create the login account in the same transaction as the Staff row:
    # a single commit below means a failure creating the login rolls back
    # the Staff row too, instead of leaving an orphaned Staff row with no
    # way to log in (see services/auth_provisioning.create_login_account).
    new_user, temp_password = _create_login_for_staff(db, name, role, commit=False)
    if new_user is not None:
        db_staff.user_id = new_user.id

    db.commit()
    db.refresh(db_staff)

    _log_activity(db, "New Staff Onboarded", f"{name} was registered as {role}.", "green")

    if file is not None:
        update_global_embeddings(db)

    return StaffResponse(
        id=db_staff.id,
        name=db_staff.name,
        role=db_staff.role,
        category=db_staff.category,
        photo_count=1 if file is not None else 0,
        photo_url=f"/{db_staff.photo_path}" if db_staff.photo_path else None,
        status=new_user.status if new_user else None,
        username=new_user.username if new_user else None,
        temp_password=temp_password,
    )


@router.post("/{staff_id}/photo", response_model=StaffPhotoResponse)
async def add_staff_photo(
    staff_id: int,
    file: UploadFile = File(...),
    label: Optional[str] = None,
    db: Session = Depends(get_db),
    _admin: models.User = Depends(require_permission("manage_staff")),
):
    """Add an additional face photo for an existing staff member."""
    staff = db.query(models.Staff).filter(models.Staff.id == staff_id).first()
    if not staff:
        raise HTTPException(status_code=404, detail="Staff member not found.")

    upload_dir = "uploads/staff"
    os.makedirs(upload_dir, exist_ok=True)
    
    filename = f"{uuid.uuid4().hex}_{file.filename}"
    file_path = os.path.join(upload_dir, filename)

    try:
        with open(file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        embedding = vision_service.extract_embedding(file_path)
        upper_embedding = vision_service.extract_upper_embedding(image_path=file_path)
        if embedding is None:
            if os.path.exists(file_path):
                os.remove(file_path)
            raise HTTPException(status_code=400, detail="No face detected in the image.")

        photo = models.StaffPhoto(
            staff_id=staff_id,
            embedding=embedding.tolist(),
            upper_embedding=(upper_embedding.tolist()
                             if upper_embedding is not None else None),
            label=label,
            photo_path=file_path
        )
        db.add(photo)
        db.commit()
        db.refresh(photo)
        
        update_global_embeddings(db)
        
        photo_url = f"/uploads/staff/{filename}" if photo.photo_path else None
        
        return StaffPhotoResponse(
            id=photo.id,
            staff_id=photo.staff_id,
            label=photo.label,
            photo_url=photo_url,
            created_at=photo.created_at
        )
    except Exception as e:
        if os.path.exists(file_path):
            os.remove(file_path)
        import traceback
        traceback.print_exc()
        print(f"[Staff] Error adding staff photo: {e}")
        raise HTTPException(status_code=500, detail="Failed to process staff photo.")


@router.get("/{staff_id}/photos", response_model=List[StaffPhotoResponse])
def get_staff_photos(staff_id: int, db: Session = Depends(get_db)):
    """List all extra photos registered for a staff member."""
    photos = db.query(models.StaffPhoto).filter(models.StaffPhoto.staff_id == staff_id).all()
    
    result = []
    for p in photos:
        photo_url = f"/{p.photo_path}" if p.photo_path else None
        result.append(StaffPhotoResponse(
            id=p.id,
            staff_id=p.staff_id,
            label=p.label,
            photo_url=photo_url,
            created_at=p.created_at
        ))
    return result


@router.delete("/{staff_id}/photo/{photo_id}")
def delete_staff_photo(
    staff_id: int,
    photo_id: int,
    db: Session = Depends(get_db),
    _admin: models.User = Depends(require_permission("manage_staff")),
):
    """Remove a specific extra photo from a staff member."""
    photo = db.query(models.StaffPhoto).filter(
        models.StaffPhoto.id == photo_id,
        models.StaffPhoto.staff_id == staff_id,
    ).first()
    if not photo:
        raise HTTPException(status_code=404, detail="Photo not found.")
    
    # Delete from filesystem
    if photo.photo_path and os.path.exists(photo.photo_path):
        os.remove(photo.photo_path)
        
    db.delete(photo)
    db.commit()
    
    update_global_embeddings(db)
    return {"status": "deleted"}


def _staff_to_response(staff: models.Staff, db: Optional[Session] = None) -> "StaffResponse":
    # Mirrors get_staff()'s photo_url resolution below exactly - a staff
    # member enrolled only through additional photos (no primary
    # embedding/photo_path set at all, e.g. Anamika) has a real photo on
    # the "front"-labeled StaffPhoto row, not on staff.photo_path. Missing
    # this fallback here (this helper backs /me, so the profile screen)
    # showed the initials placeholder even though the exact same person's
    # directory card correctly showed their photo via get_staff().
    photo_url = f"/{staff.photo_path}" if staff.photo_path else None
    if not photo_url:
        front_photo = next((p for p in staff.photos if p.label == "front"), None)
        if front_photo and front_photo.photo_path:
            photo_url = f"/{front_photo.photo_path}"

    # Resolved effective head (explicit reports_to_id, else department/
    # category head) - only computable with a db session, since it may
    # need to look up the department/category head separately from
    # whatever's already loaded on `staff`. Callers that already have a
    # session in scope should always pass it; this only falls back to the
    # raw (unresolved) reports_to_id when one genuinely isn't available.
    head = effective_head(db, staff) if db is not None else staff.reports_to

    return StaffResponse(
        id=staff.id,
        name=staff.name,
        role=staff.role,
        category=staff.category,
        photo_count=len(staff.photos) + (1 if staff.embedding is not None else 0),
        photo_url=photo_url,
        status=staff.user.status if staff.user else None,
        user_id=staff.user_id,
        can_call=staff.user_id is not None,
        shift_start=_time_to_hhmm(staff.shift_start),
        shift_end=_time_to_hhmm(staff.shift_end),
        expected_shift_hours=staff.expected_shift_hours,
        is_head=staff.is_head,
        department=staff.department,
        reports_to_id=head.id if head else None,
        reports_to_name=head.name if head else None,
    )


class SelfProfileUpdate(BaseModel):
    # Self-service is deliberately narrower than the admin StaffUpdate above
    # (which also carries role/category/shift, all admin-controlled) - a
    # staff member editing their own profile can only ever change their own
    # display name.
    name: str


# Registered ahead of the "/{staff_id}" routes below: Starlette matches
# path templates in registration order, and "/{staff_id}" (no int
# converter in the path itself) matches the literal segment "me" at the
# routing stage - if registered first, PUT/GET /api/staff/me would hit
# update_staff/that route instead and 422 on int("me") rather than ever
# reaching these.
@router.get("/me", response_model=StaffResponse)
def get_my_staff_profile(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    The logged-in user's own Staff record, for a self-service profile
    screen (view side) - reachable regardless of the "manage_staff"
    permission the admin-only /{staff_id} endpoints require, since here
    the caller is only ever looking at/editing their own row.
    """
    staff = db.query(models.Staff).filter(models.Staff.user_id == current_user.id).first()
    if staff is None:
        raise HTTPException(
            status_code=404,
            detail="No staff profile is linked to this account.",
        )
    return _staff_to_response(staff, db)


@router.put("/me", response_model=StaffResponse)
def update_my_staff_profile(
    body: SelfProfileUpdate,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    staff = db.query(models.Staff).filter(models.Staff.user_id == current_user.id).first()
    if staff is None:
        raise HTTPException(
            status_code=404,
            detail="No staff profile is linked to this account.",
        )
    name = body.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Name cannot be empty.")
    staff.name = name
    db.commit()
    db.refresh(staff)
    _log_activity(db, "Profile Updated", f"{staff.name} updated their own profile.", "orange")
    return _staff_to_response(staff, db)


@router.get("/my-team", response_model=List[StaffResponse])
def get_my_team(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """
    Everyone whose resolved effective head (services/staff/hierarchy.py)
    is the caller - the "team visibility" a head gets, distinct from the
    full People Directory. An account that isn't itself a head (or has no
    linked Staff row at all) just sees an empty team, not an error - most
    staff simply don't have one.

    Registered ahead of "/{staff_id}" for the same reason "/me" is (see
    the comment above get_my_staff_profile): an unconverted path param
    would otherwise swallow this literal segment first.
    """
    actor_staff = (
        db.query(models.Staff).filter(models.Staff.user_id == current_user.id).first()
    )
    if actor_staff is None or not actor_staff.is_head:
        return []

    team = [
        s
        for s in db.query(models.Staff).filter(models.Staff.id != actor_staff.id).all()
        if (head := effective_head(db, s)) is not None and head.id == actor_staff.id
    ]
    return [_staff_to_response(s, db) for s in team]


@router.put("/{staff_id}", response_model=StaffResponse)
def update_staff(
    staff_id: int,
    body: StaffUpdate,
    db: Session = Depends(get_db),
    _admin: models.User = Depends(require_permission("manage_staff")),
):
    """Update staff name."""
    staff = db.query(models.Staff).filter(models.Staff.id == staff_id).first()
    if not staff:
        raise HTTPException(status_code=404, detail="Staff not found.")
    if body.reports_to_id is not None:
        if body.reports_to_id == staff.id:
            raise HTTPException(status_code=400, detail="A staff member cannot report to themselves.")
        if not db.query(models.Staff).filter(models.Staff.id == body.reports_to_id).first():
            raise HTTPException(status_code=404, detail="The selected senior was not found.")
        if would_create_cycle(db, staff.id, body.reports_to_id):
            raise HTTPException(status_code=400, detail="That assignment would create a reporting cycle.")
    staff.name = body.name
    staff.role = body.role
    staff.category = body.category
    staff.shift_start = _hhmm_to_time(body.shift_start)
    staff.shift_end = _hhmm_to_time(body.shift_end)
    staff.is_head = body.is_head
    staff.department = body.department
    staff.reports_to_id = body.reports_to_id
    db.commit()
    db.refresh(staff)

    _log_activity(db, "Profile Updated", f"{staff.name} role changed to {staff.role}.", "orange")

    return _staff_to_response(staff, db)


@router.put("/{staff_id}/assignment", response_model=StaffResponse)
def update_staff_assignment(
    staff_id: int,
    body: StaffAssignmentUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """
    Lets a HEAD (re)assign one of their own reports - deliberately not
    gated by manage_staff, since that permission is broader (name/role/
    category/shift/is_head) than a head should need just to organize their
    own team. Authorization is services/staff/hierarchy.can_assign, not a
    static permission: it's "are you this person's current head (or
    manage_staff/admin)", resolved fresh against the current state of the
    hierarchy on every call.
    """
    staff = db.query(models.Staff).filter(models.Staff.id == staff_id).first()
    if not staff:
        raise HTTPException(status_code=404, detail="Staff not found.")
    if not can_assign(db, current_user, staff):
        raise HTTPException(
            status_code=403,
            detail="Only this person's current head (or an administrator) can reassign them.",
        )
    if body.reports_to_id is not None:
        if body.reports_to_id == staff.id:
            raise HTTPException(status_code=400, detail="A staff member cannot report to themselves.")
        if not db.query(models.Staff).filter(models.Staff.id == body.reports_to_id).first():
            raise HTTPException(status_code=404, detail="The selected senior was not found.")
        if would_create_cycle(db, staff.id, body.reports_to_id):
            raise HTTPException(status_code=400, detail="That assignment would create a reporting cycle.")

    staff.department = body.department
    staff.reports_to_id = body.reports_to_id
    db.commit()
    db.refresh(staff)

    _log_activity(db, "Team Assignment Updated", f"{staff.name}'s reporting assignment was updated.", "blue")

    return _staff_to_response(staff, db)


@router.delete("/{staff_id}")
def delete_staff(
    staff_id: int,
    db: Session = Depends(get_db),
    _admin: models.User = Depends(require_permission("manage_staff")),
):
    """
    "Revoke" a staff member. This used to hard-delete the Staff row (and
    its photos/embeddings) entirely; it now only disables their linked
    login account (status -> "inactive") so the row, photos, and
    attendance history stay in the database — nothing to recover from a
    backup if a revoke turns out to be a mistake, and the staff list can
    keep showing them with their current status instead of silently
    disappearing.
    """
    staff = db.query(models.Staff).filter(models.Staff.id == staff_id).first()
    if not staff:
        raise HTTPException(status_code=404, detail="Staff not found.")

    if staff.user is not None:
        staff.user.status = "inactive"
        db.commit()

    _log_activity(db, "Access Revoked", f"{staff.name}'s access was revoked.", "red")

    return {"status": "revoked"}


class PaginatedStaffResponse(BaseModel):
    items: List[StaffResponse]
    total: int
    page: int
    limit: int


@router.get("", response_model=PaginatedStaffResponse)
def get_staff(
    page: int = Query(1, ge=1),
    limit: int = Query(DEFAULT_PAGE_SIZE, ge=1, le=MAX_PAGE_SIZE),
    db: Session = Depends(get_db),
):
    """
    Paginated staff listing - an unbounded "all rows" query here doesn't
    scale as the roster grows, so this always returns a page (page=1/
    limit=50 by default) plus the total row count so a client can page
    through the rest.
    """
    total = db.query(models.Staff).count()
    staff_records = (
        db.query(models.Staff)
        .order_by(models.Staff.id)
        .offset((page - 1) * limit)
        .limit(limit)
        .all()
    )
    items = [_staff_to_response(s, db) for s in staff_records]
    return PaginatedStaffResponse(items=items, total=total, page=page, limit=limit)

@router.get("/activity", response_model=List[StaffActivityResponse])
def get_activity(db: Session = Depends(get_db)):
    activities = db.query(models.StaffActivity).order_by(models.StaffActivity.created_at.desc()).limit(10).all()
    return activities


def _extract_staff_video_faces(temp_path: str, upload_dir: str) -> list:
    """
    Blocking work extracted from setup_staff_video(): reads the uploaded
    video frame-by-frame with OpenCV, runs face detection/pose scoring on
    every 5th frame, and keeps the best-scoring frame per target angle.
    This is a genuinely blocking, CPU-bound per-frame loop (plus per-angle
    embedding extraction), so it must run in a worker thread via
    run_in_threadpool rather than inline in the async route - otherwise it
    blocks the event loop and starves other concurrent requests of DB
    connections (see /investigate 2026-09-20). Returns a list of dicts
    ready to become StaffPhoto rows; no DB access happens in here.
    """
    cap = cv2.VideoCapture(temp_path)
    if not cap.isOpened():
        raise Exception("Failed to open video file")

    best_faces = {
        "front": {"score": -1, "frame": None, "embedding": None},
        "side_left": {"score": -1, "frame": None, "embedding": None},
        "side_right": {"score": -1, "frame": None, "embedding": None},
        "angled_down": {"score": -1, "frame": None, "embedding": None},
        "angled_up": {"score": -1, "frame": None, "embedding": None},
    }

    frame_idx = 0
    while True:
        ret, frame = cap.read()
        if not ret:
            break

        # Process every 5th frame to save CPU while catching fast movements
        if frame_idx % 5 == 0:
            faces = vision_service.app.get(frame)
            if faces:
                # Pick largest face
                face = max(faces, key=lambda f: (f.bbox[2]-f.bbox[0])*(f.bbox[3]-f.bbox[1]))
                pitch, yaw, roll = face.pose
                score = float(face.det_score)

                bucket = None
                if abs(yaw) < 15 and abs(pitch) < 15:
                    bucket = "front"
                elif yaw < -25 and abs(pitch) < 20:
                    bucket = "side_left"
                elif yaw > 25 and abs(pitch) < 20:
                    bucket = "side_right"
                elif pitch > 20 and abs(yaw) < 20:
                    bucket = "angled_up"
                elif pitch < -20 and abs(yaw) < 20:
                    bucket = "angled_down"

                if bucket and score > best_faces[bucket]["score"]:
                    best_faces[bucket]["score"] = score
                    best_faces[bucket]["frame"] = frame.copy()
                    best_faces[bucket]["embedding"] = face.embedding

        frame_idx += 1

    cap.release()
    os.remove(temp_path)

    extracted = []
    for bucket, data in best_faces.items():
        if data["frame"] is not None:
            filename = f"{uuid.uuid4().hex}_{bucket}.jpg"
            file_path = os.path.join(upload_dir, filename)
            cv2.imwrite(file_path, data["frame"])
            upper_embedding = vision_service.extract_upper_embedding(
                image_path=file_path
            )
            extracted.append({
                "label": bucket,
                "embedding": data["embedding"].tolist(),
                "upper_embedding": (upper_embedding.tolist()
                                     if upper_embedding is not None else None),
                "photo_path": file_path,
            })
    return extracted


@router.post("/{staff_id}/video_setup")
async def setup_staff_video(
    staff_id: int,
    file: UploadFile = File(...),
    db: Session = Depends(get_db)
):
    """Process a short video to auto-extract multiple facial angles (Apple Face ID style)."""
    staff = db.query(models.Staff).filter(models.Staff.id == staff_id).first()
    if not staff:
        raise HTTPException(status_code=404, detail="Staff member not found.")

    upload_dir = "uploads/staff"
    os.makedirs(upload_dir, exist_ok=True)

    temp_filename = f"temp_vid_{uuid.uuid4().hex}_{file.filename}"
    temp_path = os.path.join(upload_dir, temp_filename)

    # No further DB access is needed until after the video is processed -
    # release the pooled connection now instead of holding it idle for the
    # duration of the (potentially multi-second) frame loop below. The
    # session reconnects transparently on its next use (db.add/commit
    # further down).
    db.close()

    try:
        with open(temp_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        # The per-frame OpenCV/face-model loop is CPU-bound and blocking -
        # run it in a worker thread so it doesn't block the event loop.
        extracted_photos = await run_in_threadpool(
            _extract_staff_video_faces, temp_path, upload_dir
        )

        extracted_count = 0
        for photo_data in extracted_photos:
            photo = models.StaffPhoto(
                staff_id=staff_id,
                embedding=photo_data["embedding"],
                upper_embedding=photo_data["upper_embedding"],
                label=photo_data["label"],
                photo_path=photo_data["photo_path"],
            )
            db.add(photo)
            extracted_count += 1

        db.commit()
        update_global_embeddings(db)

        return {"status": "success", "extracted_count": extracted_count}

    except Exception as e:
        if os.path.exists(temp_path):
            os.remove(temp_path)
        import traceback
        traceback.print_exc()
        print(f"[Staff] Error processing video setup: {e}")
        raise HTTPException(status_code=500, detail="Failed to process video setup.")

@ws_router.websocket("/{staff_id}/live_setup/ws")
async def live_setup_ws(websocket: WebSocket, staff_id: int, db: Session = Depends(get_db)):
    """Live interactive 3D face registration endpoint."""
    await websocket.accept()
    
    staff = db.query(models.Staff).filter(models.Staff.id == staff_id).first()
    if not staff:
        await websocket.close(code=1008)
        return

    upload_dir = "uploads/staff"
    os.makedirs(upload_dir, exist_ok=True)
    
    # State tracking
    angles = ["front", "side_left", "side_right", "angled_up", "angled_down"]
    instructions = {
        "front": "Look straight at the camera.",
        "side_left": "Turn your head slowly to the left.",
        "side_right": "Turn your head slowly to the right.",
        "angled_up": "Tilt your head slightly upward.",
        "angled_down": "Tilt your head slightly downward.",
    }
    
    completed = []
    captured_data = []
    current_idx = 0
    
    def get_current_angle():
        if current_idx < len(angles):
            return angles[current_idx]
        return None
        
    try:
        # Send initial state
        current = get_current_angle()
        await websocket.send_json({
            "status": "capturing",
            "instruction": instructions[current],
            "completed": completed
        })
        
        while current_idx < len(angles):
            # Receive JPEG frame bytes from Flutter
            data = await websocket.receive_bytes()
            
            # Decode JPEG
            np_arr = np.frombuffer(data, np.uint8)
            frame = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
            
            if frame is None:
                continue
                
            current_target = angles[current_idx]
            base_instruction = instructions[current_target]
                
            # Process face
            from camera.model_manager import ModelManager
            face_app = ModelManager().get_face_analysis()
            faces = face_app.get(frame) if face_app else []
            if not faces:
                await websocket.send_json({
                    "status": "capturing",
                    "instruction": "No face detected.",
                    "completed": completed
                })
                continue
                
            # Find largest face
            face = max(faces, key=lambda f: (f.bbox[2]-f.bbox[0])*(f.bbox[3]-f.bbox[1]))
            
            h, w = frame.shape[:2]
            x1, y1, x2, y2 = face.bbox
            face_w = x2 - x1
            
            # Require the face box to be entirely inside a central "safe zone"
            # 10% margin on sides, 15% margin on top/bottom
            valid_x1 = w * 0.10
            valid_x2 = w * 0.90
            valid_y1 = h * 0.15
            valid_y2 = h * 0.85
            
            if x1 < valid_x1 or x2 > valid_x2 or y1 < valid_y1 or y2 > valid_y2:
                await websocket.send_json({
                    "status": "capturing", 
                    "instruction": "Please keep your face completely inside the circle.", 
                    "completed": completed
                })
                continue
                
            # Check if face is large enough (at least 12% of width)
            if face_w < w * 0.12:
                await websocket.send_json({
                    "status": "capturing", 
                    "instruction": "Please move closer.", 
                    "completed": completed
                })
                continue
                
            pitch, yaw, roll = face.pose
            
            match = False
            
            # Check if pose matches target
            if current_target == "front" and abs(yaw) < 15 and abs(pitch) < 15:
                match = True
            elif current_target == "side_left" and yaw < -25 and abs(pitch) < 20:
                match = True
            elif current_target == "side_right" and yaw > 25 and abs(pitch) < 20:
                match = True
            elif current_target == "angled_up" and pitch > 20 and abs(yaw) < 20:
                match = True
            elif current_target == "angled_down" and pitch < -20 and abs(yaw) < 20:
                match = True
                
            if not match:
                await websocket.send_json({
                    "status": "capturing", 
                    "instruction": base_instruction, 
                    "completed": completed
                })
                
            if match:
                upper_embedding = vision_service.extract_upper_embedding(
                    img=frame, bbox=face.bbox.astype(int)
                )
                # Store the normal and upper-face embeddings for masked matching.
                captured_data.append({
                    "target": current_target,
                    "frame": frame,
                    "embedding": face.embedding.tolist(),
                    "upper_embedding": (
                        upper_embedding.tolist()
                        if upper_embedding is not None
                        else None
                    ),
                })
                
                completed.append(current_target)
                current_idx += 1
                
                next_angle = get_current_angle()
                if next_angle:
                    await websocket.send_json({
                        "status": "capturing",
                        "instruction": instructions[next_angle],
                        "completed": completed
                    })
                else:
                    break
        
        # All done, now save to DB
        for item in captured_data:
            filename = f"{uuid.uuid4().hex}_{item['target']}.jpg"
            file_path = os.path.join(upload_dir, filename)
            cv2.imwrite(file_path, item['frame'])
            
            photo = models.StaffPhoto(
                staff_id=staff_id,
                embedding=item['embedding'],
                upper_embedding=item['upper_embedding'],
                label=item['target'],
                photo_path=file_path
            )
            db.add(photo)
        db.commit()
        
        update_global_embeddings(db)
        
        await websocket.send_json({
            "status": "complete",
            "instruction": "All angles captured successfully!",
            "completed": completed
        })
        await websocket.close()
        
    except WebSocketDisconnect:
        print("[LiveSetup] Client disconnected")
    except Exception as e:
        import traceback
        traceback_str = traceback.format_exc()
        print(f"[LiveSetup] Error: {e}")
        with open("/tmp/backend_err.txt", "w") as f:
            f.write(traceback_str)
        try:
            await websocket.close(code=1011)
        except:
            pass


class CreateStaffLoginResponse(BaseModel):
    username: str
    temp_password: str


@router.post("/{staff_id}/create-login", response_model=CreateStaffLoginResponse)
def create_login_for_existing_staff(
    staff_id: int,
    db: Session = Depends(get_db),
    _admin: models.User = Depends(require_permission("manage_staff")),
):
    """
    Retroactively provisions a login for a Staff row that predates login
    creation (or whose original account creation failed) - needed for a
    doctor to receive portal calls, since that requires Staff.user_id.
    """
    staff = db.query(models.Staff).filter(models.Staff.id == staff_id).first()
    if not staff:
        raise HTTPException(status_code=404, detail="Staff member not found")
    if staff.user_id is not None:
        raise HTTPException(status_code=400, detail="This staff member already has a login account.")

    new_user, temp_password = create_login_account(db, staff.name, staff.role or "Medical Staff", fallback_username="staff")
    if new_user is None:
        raise HTTPException(status_code=500, detail="Failed to create login account.")

    staff.user_id = new_user.id
    db.commit()

    return CreateStaffLoginResponse(username=new_user.username, temp_password=temp_password)


class DoctorDirectoryEntry(BaseModel):
    staff_id: int
    user_id: Optional[int] = None
    name: str
    role: Optional[str] = None
    can_call: bool


@router.get("/doctors", response_model=List[DoctorDirectoryEntry])
def list_doctors(db: Session = Depends(get_db)):
    """
    Directory of all doctor-category staff, for admin to call/chat with.
    """
    doctors = db.query(models.Staff).filter(models.Staff.category == "Doctor").all()
    return [
        DoctorDirectoryEntry(
            staff_id=s.id, user_id=s.user_id, name=s.name, role=s.role,
            can_call=s.user_id is not None,
        )
        for s in doctors
    ]


class MyPatientEntry(BaseModel):
    id: int
    name: str
    mrn: Optional[str] = None
    user_id: Optional[int] = None
    can_call: bool
    last_consultation: Optional[datetime.datetime] = None


@router.get("/{staff_id}/patients", response_model=List[MyPatientEntry])
def get_staff_patients(
    staff_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
):
    """
    Patients this doctor has consulted (derived from Consultation.staff_id)
    - only the doctor themself or an admin/superadmin may view this.
    """
    staff = db.query(models.Staff).filter(models.Staff.id == staff_id).first()
    if not staff:
        raise HTTPException(status_code=404, detail="Staff member not found")
    is_self = staff.user_id is not None and staff.user_id == current_user.id
    if not is_self and current_user.role not in ("admin", "superadmin"):
        raise HTTPException(status_code=403, detail="You do not have access to this doctor's patient list.")

    rows = (
        db.query(models.Patient, func.max(models.Consultation.date).label("last_consultation"))
        .join(models.Consultation, models.Consultation.patient_id == models.Patient.id)
        .filter(models.Consultation.staff_id == staff_id)
        .group_by(models.Patient.id)
        .order_by(func.max(models.Consultation.date).desc())
        .all()
    )
    return [
        MyPatientEntry(
            id=patient.id, name=patient.name, mrn=patient.mrn,
            user_id=patient.user_id, can_call=patient.user_id is not None,
            last_consultation=last_consultation,
        )
        for patient, last_consultation in rows
    ]
