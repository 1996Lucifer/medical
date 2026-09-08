import os
import re
import secrets
import string
import shutil
import datetime
import uuid
import cv2
import numpy as np
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session
from pydantic import BaseModel, ConfigDict

from database import get_db
import models
from camera.vision_service import vision_service
from routers.auth import get_password_hash

router = APIRouter(prefix="/api/staff", tags=["staff"])
ws_router = APIRouter(prefix="/api/staff", tags=["staff_ws"])

# Characters excluded from generated temp passwords/usernames: visually
# ambiguous (l/I/1/O/0) so an admin reading it aloud to a new hire doesn't
# transcribe it wrong.
_TEMP_PASSWORD_ALPHABET = "".join(
    c for c in (string.ascii_letters + string.digits) if c not in "lIO01"
)


def _generate_staff_username(db: Session, name: str) -> str:
    base = re.sub(r"[^a-z0-9]+", ".", name.strip().lower()).strip(".")
    if not base:
        base = "staff"
    candidate = base
    suffix = 1
    while db.query(models.User).filter(models.User.username == candidate).first():
        suffix += 1
        candidate = f"{base}{suffix}"
    return candidate


def _generate_temp_password(length: int = 10) -> str:
    return "".join(secrets.choice(_TEMP_PASSWORD_ALPHABET) for _ in range(length))


def _create_login_for_staff(db: Session, name: str, role: Optional[str]):
    """
    Create a login account alongside a new Staff (biometric) record, with a
    system-generated temporary password. The account starts in
    "change_password" status so the first login forces a change — the
    admin communicates this one-time password to the new hire, it is
    never stored or shown again.
    Returns (models.User, plaintext_temp_password), or (None, None) if
    account creation failed — staff registration itself must not be
    blocked by this.
    """
    try:
        username = _generate_staff_username(db, name)
        temp_password = _generate_temp_password()
        new_user = models.User(
            username=username,
            hashed_password=get_password_hash(temp_password),
            role=role or "Medical Staff",
            status="change_password",
        )
        db.add(new_user)
        db.commit()
        db.refresh(new_user)
        return new_user, temp_password
    except Exception as e:
        db.rollback()
        print(f"[Staff] Failed to create login account for {name}: {e}")
        return None, None


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
    # Only populated on the creation response — a one-time temporary
    # credential the admin must relay to the new hire. Never re-sent by
    # any other endpoint (the plaintext isn't stored anywhere).
    username: Optional[str] = None
    temp_password: Optional[str] = None
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


class StaffUpdate(BaseModel):
    name: str
    role: Optional[str] = "Medical Staff"
    category: Optional[str] = "Medical Staff"


def load_staff_list(db: Session) -> list:
    """
    Load ALL embeddings for all staff members — both the primary photo
    and every additional photo — as a flat list of {name, embedding}.
    """
    staff_records = db.query(models.Staff).all()
    staff_list = []
    for s in staff_records:
        if s.embedding:
            staff_list.append({"id": s.id, "name": s.name, "embedding": s.embedding, "upper_embedding": s.upper_embedding})
        for photo in s.photos:
            staff_list.append({"id": s.id, "name": s.name, "embedding": photo.embedding, "upper_embedding": photo.upper_embedding})
    return staff_list

def update_global_embeddings(db: Session):
    staff_list = load_staff_list(db)
    vision_service.update_staff_embeddings(staff_list)
    # The multi-camera zone service runs in a separate process, so it needs
    # the same refreshed identity set without waiting for a camera restart.
    from camera.vision_worker import vision_process_manager
    vision_process_manager.update_staff(staff_list)


@router.post("", response_model=StaffResponse)
async def register_staff(
    name: str,
    role: Optional[str] = "Medical Staff",
    category: Optional[str] = "Medical Staff",
    file: Optional[UploadFile] = None,
    db: Session = Depends(get_db),
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
            raise HTTPException(status_code=500, detail=str(e))

    db.add(db_staff)
    db.commit()
    db.refresh(db_staff)

    _log_activity(db, "New Staff Onboarded", f"{name} was registered as {role}.", "green")

    if file is not None:
        update_global_embeddings(db)

    new_user, temp_password = _create_login_for_staff(db, name, role)
    if new_user is not None:
        db_staff.user_id = new_user.id
        db.commit()
        db.refresh(db_staff)

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
        raise HTTPException(status_code=500, detail=str(e))


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
def delete_staff_photo(staff_id: int, photo_id: int, db: Session = Depends(get_db)):
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


@router.put("/{staff_id}", response_model=StaffResponse)
def update_staff(staff_id: int, body: StaffUpdate, db: Session = Depends(get_db)):
    """Update staff name."""
    staff = db.query(models.Staff).filter(models.Staff.id == staff_id).first()
    if not staff:
        raise HTTPException(status_code=404, detail="Staff not found.")
    staff.name = body.name
    staff.role = body.role
    staff.category = body.category
    db.commit()
    db.refresh(staff)

    _log_activity(db, "Profile Updated", f"{staff.name} role changed to {staff.role}.", "orange")

    photo_url = f"/{staff.photo_path}" if staff.photo_path else None

    return StaffResponse(
        id=staff.id,
        name=staff.name,
        role=staff.role,
        category=staff.category,
        photo_count=len(staff.photos) + (1 if staff.embedding is not None else 0),
        photo_url=photo_url,
        status=staff.user.status if staff.user else None,
    )


@router.delete("/{staff_id}")
def delete_staff(staff_id: int, db: Session = Depends(get_db)):
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


@router.get("", response_model=List[StaffResponse])
def get_staff(db: Session = Depends(get_db)):
    staff_records = db.query(models.Staff).all()
    result = []
    for s in staff_records:
        count = 1 if s.embedding is not None else 0
        count += len(s.photos)

        photo_url = f"/{s.photo_path}" if s.photo_path else None
        if not photo_url:
            front_photo = next((p for p in s.photos if p.label == 'front'), None)
            if front_photo and front_photo.photo_path:
                photo_url = f"/{front_photo.photo_path}"

        result.append(StaffResponse(
            id=s.id,
            name=s.name,
            role=s.role,
            category=s.category,
            photo_count=count,
            photo_url=photo_url,
            status=s.user.status if s.user else None,
        ))
    return result

@router.get("/activity", response_model=List[StaffActivityResponse])
def get_activity(db: Session = Depends(get_db)):
    activities = db.query(models.StaffActivity).order_by(models.StaffActivity.created_at.desc()).limit(10).all()
    return activities


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
    
    try:
        with open(temp_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
            
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
        
        extracted_count = 0
        for bucket, data in best_faces.items():
            if data["frame"] is not None:
                filename = f"{uuid.uuid4().hex}_{bucket}.jpg"
                file_path = os.path.join(upload_dir, filename)
                cv2.imwrite(file_path, data["frame"])
                upper_embedding = vision_service.extract_upper_embedding(
                    image_path=file_path
                )
                
                # Create StaffPhoto entry
                photo = models.StaffPhoto(
                    staff_id=staff_id,
                    embedding=data["embedding"].tolist(),
                    upper_embedding=(upper_embedding.tolist()
                                     if upper_embedding is not None else None),
                    label=bucket,
                    photo_path=file_path
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
        raise HTTPException(status_code=500, detail=str(e))

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
