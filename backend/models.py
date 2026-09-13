import datetime

from database import Base
from pgvector.sqlalchemy import Vector
from sqlalchemy import (
    Boolean,
    Column,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Table,
    Text,
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

# ── RBAC Association Tables ────────────────────────────────────────
user_groups = Table(
    "user_groups",
    Base.metadata,
    Column("user_id", Integer, ForeignKey("users.id"), primary_key=True),
    Column("group_id", Integer, ForeignKey("rbac_groups.id"), primary_key=True),
)

group_permissions = Table(
    "group_permissions",
    Base.metadata,
    Column("group_id", Integer, ForeignKey("rbac_groups.id"), primary_key=True),
    Column(
        "permission_id", Integer, ForeignKey("rbac_permissions.id"), primary_key=True
    ),
)

user_permissions = Table(
    "user_permissions",
    Base.metadata,
    Column("user_id", Integer, ForeignKey("users.id"), primary_key=True),
    Column(
        "permission_id", Integer, ForeignKey("rbac_permissions.id"), primary_key=True
    ),
)


class RBACGroup(Base):
    __tablename__ = "rbac_groups"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, index=True, nullable=False)
    description = Column(String, nullable=True)

    users = relationship("User", secondary=user_groups, back_populates="groups")
    permissions = relationship(
        "RBACPermission", secondary=group_permissions, back_populates="groups"
    )


class RBACPermission(Base):
    __tablename__ = "rbac_permissions"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, index=True, nullable=False)
    description = Column(String, nullable=True)

    groups = relationship(
        "RBACGroup", secondary=group_permissions, back_populates="permissions"
    )
    users = relationship(
        "User", secondary=user_permissions, back_populates="direct_permissions"
    )


class User(Base):
    """
    Admin user for Role-Based Access Control (RBAC).
    """

    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    role = Column(String, nullable=False, default="admin")
    # Account lifecycle, kept in one place instead of deleting rows (e.g.
    # "Revoke" on a staff member) so history/audit trail is preserved:
    #   - "active": normal login.
    #   - "change_password": login succeeds but the caller must change the
    #     password before using the app (system-generated temp password,
    #     e.g. a newly onboarded staff member).
    #   - "inactive": login is refused outright ("Access Denied. Contact
    #     admin.") — this is what "Revoke" sets instead of deleting the row.
    #   - "pending": reserved, behavior not defined yet.
    status = Column(String, nullable=False, default="active")
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    groups = relationship("RBACGroup", secondary=user_groups, back_populates="users")
    direct_permissions = relationship(
        "RBACPermission", secondary=user_permissions, back_populates="users"
    )
    # The Patient record this login belongs to, if this is a patient-portal
    # account (role == "patient") rather than a staff/admin account.
    patient_profile = relationship("Patient", back_populates="user", uselist=False)


class Patient(Base):
    """
    Centralized Patient record for scalability.
    """

    __tablename__ = "patients"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, index=True, nullable=False)
    mrn = Column(
        String, unique=True, index=True, nullable=True
    )  # Medical Record Number
    dob = Column(Date, nullable=True)
    gender = Column(String, nullable=True)
    # The patient's own login account (portal access + calling), created via
    # POST /api/patients/{id}/create-login. Nullable because most existing
    # patient rows predate portal access and were never given one.
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    consultations = relationship(
        "Consultation", back_populates="patient", cascade="all, delete-orphan"
    )
    medical_reports = relationship(
        "MedicalReport", back_populates="patient", cascade="all, delete-orphan"
    )
    user = relationship("User", back_populates="patient_profile")


class Consultation(Base):
    __tablename__ = "consultations"

    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id"), nullable=False)
    # Which doctor conducted this consultation - drives "which doctors has
    # this patient seen" (patient portal call list) and "which patients has
    # this doctor seen" (doctor's patient list), both used to authorize who
    # a patient/doctor is allowed to call. Nullable because consultations
    # created before this existed have no recorded doctor.
    staff_id = Column(Integer, ForeignKey("staff.id"), nullable=True)
    date = Column(DateTime(timezone=True), server_default=func.now())
    transcript = Column(Text, nullable=True)
    discharge_summary = Column(Text, nullable=True)
    prescription = Column(Text, nullable=True)

    patient = relationship("Patient", back_populates="consultations")
    staff = relationship("Staff")

    @property
    def patient_name(self):
        return self.patient.name if self.patient else None

    # Whoever actually conducted this consultation - a doctor OR a nurse,
    # both attend/refer patients through the same Consultation flow. Before
    # this, staff_id was recorded in the DB but never surfaced through the
    # API/UI at all, so no attending name ever appeared on a record
    # regardless of role.
    @property
    def staff_name(self):
        return self.staff.name if self.staff else None

    @property
    def staff_role(self):
        return self.staff.role if self.staff else None


class MedicalReport(Base):
    __tablename__ = "medical_reports"

    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id"), nullable=False)
    date = Column(DateTime(timezone=True), server_default=func.now())
    file_path = Column(String, nullable=True)
    key_findings = Column(Text, nullable=True)
    abnormalities = Column(Text, nullable=True)
    recommendations = Column(Text, nullable=True)
    vitals_extracted = Column(Text, nullable=True)
    raw_response = Column(Text, nullable=True)

    patient = relationship("Patient", back_populates="medical_reports")

    @property
    def patient_name(self):
        return self.patient.name if self.patient else None


from sqlalchemy.orm import relationship


class Staff(Base):
    __tablename__ = "staff"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, index=True)
    role = Column(String, nullable=True, default="Medical Staff")
    # Broad staff category (Doctor, Nurse, Security, Morgue, ...) — distinct
    # from `role`, which is a specific job title (e.g. "Head of Radiology").
    # Used for filtering/grouping in the staff list.
    category = Column(String, nullable=True, default="Medical Staff")
    embedding = Column(Vector(512))  # Primary (first) photo embedding
    upper_embedding = Column(
        Vector(512), nullable=True
    )  # Upper 45% mask tracking embedding
    photo_path = Column(String, nullable=True)  # Path to the saved photo file
    # The login account created alongside this staff member at onboarding
    # (see routers/staff.py::_create_login_for_staff). Nullable because
    # staff created before this existed have no linked account.
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    # Additional photos for multi-angle recognition
    photos = relationship(
        "StaffPhoto", back_populates="staff", cascade="all, delete-orphan"
    )
    user = relationship("User")


class StaffPhoto(Base):
    """
    Extra face photos per staff member.
    Allows registration of front, left-side, right-side, angled views
    so the AI can recognise them from any angle.
    """

    __tablename__ = "staff_photos"

    id = Column(Integer, primary_key=True, index=True)
    staff_id = Column(Integer, ForeignKey("staff.id"), nullable=False)
    embedding = Column(Vector(512), nullable=False)
    upper_embedding = Column(Vector(512), nullable=True)
    label = Column(String, nullable=True)  # e.g. "front", "left", "right", "angled"
    photo_path = Column(String, nullable=True)  # Path to the saved photo file
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    staff = relationship("Staff", back_populates="photos")


class StaffActivity(Base):
    __tablename__ = "staff_activity"
    id = Column(Integer, primary_key=True, index=True)
    title = Column(String, nullable=False)
    subtitle = Column(String, nullable=False)
    color = Column(String, nullable=False)  # e.g. "green", "orange", "red"
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class Camera(Base):
    """
    A registered RTSP camera with a human-readable name and location.
    Attendance records are linked to the camera that detected the person.
    """

    __tablename__ = "cameras"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)  # e.g. "Main Entrance"
    location = Column(String, nullable=True)  # e.g. "Ground Floor, Block A"
    ip_address = Column(
        String, nullable=False, default="127.0.0.1"
    )  # e.g. "192.168.1.100"
    port = Column(Integer, nullable=False, default=554)
    username = Column(String, nullable=True)
    password = Column(String, nullable=True)
    stream_path = Column(String, nullable=True, default="")
    is_restricted = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    security_alerts = relationship("SecurityAlert", back_populates="camera")
    rois = relationship(
        "CameraROI", back_populates="camera", cascade="all, delete-orphan"
    )

    @property
    def rtsp_url(self) -> str:
        cred = ""
        if self.username or self.password:
            user = self.username or ""
            pwd = self.password or ""
            cred = f"{user}:{pwd}@"
        path = self.stream_path or ""
        if path and not path.startswith("/"):
            path = "/" + path
        ip = self.ip_address or "127.0.0.1"
        port = self.port or 554
        return f"rtsp://{cred}{ip}:{port}{path}"


class CameraROI(Base):
    """
    Region of Interest (ROI) mapping for a specific camera.
    points: JSON array of normalized coordinates, e.g., [{"x": 0.1, "y": 0.2}, ...]
    zone_type: 'observation', 'verification', or 'restricted'
    """

    __tablename__ = "camera_rois"

    id = Column(Integer, primary_key=True, index=True)
    camera_id = Column(Integer, ForeignKey("cameras.id"), nullable=False)
    zone_name = Column(
        String, index=True, nullable=False
    )  # e.g. 'ICU', 'Operating Room'
    zone_type = Column(
        String, nullable=False, default="observation"
    )  # observation | verification | restricted
    points = Column(Text, nullable=False)  # JSON array

    camera = relationship("Camera", back_populates="rois")


class Attendance(Base):
    """
    Represents one attendance *session* per staff member per day.
    A new session is only created when a person hasn't been seen for
    SESSION_GAP_HOURS (5 hours) — prevents duplicate entries across a shift.

    entry_time  — when first detected (start of session)
    last_seen   — updated ~every 30 seconds while still visible on camera
    exit_time   — set manually via the checkout API (or auto-inferred)
    camera_id   — which camera detected the person (FK to cameras table)
    camera_name — denormalised label for fast display
    """

    __tablename__ = "attendance"

    id = Column(Integer, primary_key=True, index=True)
    staff_id = Column(
        Integer, ForeignKey("staff.id", ondelete="SET NULL"), nullable=True
    )
    staff = relationship("Staff", foreign_keys=[staff_id])
    staff_name = Column(String, index=True, nullable=False)
    # Best face-match score at entry. Nullable because RFID-sourced sessions
    # (see `source` below) have no face-match confidence to record.
    confidence = Column(Float, nullable=True)
    date = Column(Date, nullable=False, default=datetime.date.today)
    entry_time = Column(DateTime(timezone=True), server_default=func.now())
    last_seen = Column(
        DateTime(timezone=True), server_default=func.now(), nullable=True
    )
    exit_time = Column(DateTime(timezone=True), nullable=True)  # manual checkout
    camera_id = Column(Integer, ForeignKey("cameras.id"), nullable=True)
    camera_name = Column(String, nullable=True)  # e.g. "Main Entrance"
    # Which channel produced this session: "face" (camera recognition,
    # default — preserves behavior for all rows/code paths that predate this
    # column), "rfid" (badge tap at an enroll/verify device), or "manual"
    # (admin-created/edited).
    source = Column(String, nullable=False, default="face", server_default="face")

    @property
    def role(self) -> str:
        return self.staff.role if self.staff and self.staff.role else "Medical Staff"


class RfidDevice(Base):
    """
    A physical ESP32+RC522 device (enrollment writer or verification reader
    terminal — see /Users/dj/Projects/kram/rfid-firmware). Authenticates
    purely via `Authorization: Bearer <raw key>`; only the SHA-256 hash of
    that raw key is ever stored (see routers/rfid.py's device-bearer
    dependency, which hashes the incoming header and compares).
    """

    __tablename__ = "rfid_devices"

    id = Column(Integer, primary_key=True, index=True)
    label = Column(String, nullable=False)  # e.g. "Main Entrance Reader"
    device_key_hash = Column(String, unique=True, index=True, nullable=False)
    is_active = Column(Boolean, nullable=False, default=True)
    last_seen_at = Column(DateTime(timezone=True), nullable=True)
    # Self-reported by the device on every WiFi (re)connect via POST
    # /api/rfid/checkin - never entered by hand. This is what lets an admin
    # remotely reset the station (POST /api/rfid/station/reset-config)
    # without anyone needing Serial Monitor access or manual .env edits,
    # even after a DHCP lease hands it a new IP.
    ip_address = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class RfidCard(Base):
    """
    One active badge per staff member. The card itself only ever stores an
    AES-256-GCM-encrypted opaque 128-bit token (see the firmware's security
    design) — the token's real identity mapping only exists here, and even
    here only its SHA-256 hash is stored, never the raw token.
    """

    __tablename__ = "rfid_cards"

    id = Column(Integer, primary_key=True, index=True)
    staff_id = Column(
        Integer, ForeignKey("staff.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    token_hash = Column(String, unique=True, index=True, nullable=False)
    issued_at = Column(DateTime(timezone=True), server_default=func.now())
    revoked_at = Column(DateTime(timezone=True), nullable=True)

    staff = relationship("Staff")


class RfidEnrollSession(Base):
    """
    A short-lived (90s) window during which the next `POST /api/rfid/enroll`
    call from `device_id` is bound to `staff_id`. Created by an admin from
    the Flutter enroll-card flow immediately before tapping a blank card on
    the writer device; the writer has no idea which staff member it's
    enrolling for, so this session is what supplies that mapping.
    """

    __tablename__ = "rfid_enroll_sessions"

    id = Column(Integer, primary_key=True, index=True)
    device_id = Column(Integer, ForeignKey("rfid_devices.id"), nullable=False)
    staff_id = Column(Integer, ForeignKey("staff.id"), nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    consumed_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    device = relationship("RfidDevice")
    staff = relationship("Staff")


class EquipmentType(Base):
    __tablename__ = "equipment_types"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(
        String, unique=True, index=True, nullable=False
    )  # e.g. "Wheelchair", "Ventilator"


class EquipmentItem(Base):
    """
    Specific instance of equipment.
    """

    __tablename__ = "equipment_items"

    id = Column(Integer, primary_key=True, index=True)
    equipment_id = Column(
        String, unique=True, index=True, nullable=False
    )  # e.g. "Wheelchair #12"
    type_id = Column(Integer, ForeignKey("equipment_types.id"), nullable=False)
    current_location = Column(
        String, nullable=True
    )  # Last known location based on camera
    last_seen = Column(DateTime(timezone=True), nullable=True)

    # Optional relationship
    # type = relationship("EquipmentType")


class EquipmentTracking(Base):
    """
    Log of equipment movement.
    """

    __tablename__ = "equipment_tracking"

    id = Column(Integer, primary_key=True, index=True)
    equipment_item_id = Column(
        Integer, ForeignKey("equipment_items.id"), nullable=False
    )
    camera_id = Column(Integer, ForeignKey("cameras.id"), nullable=True)
    camera_name = Column(String, nullable=True)
    timestamp = Column(DateTime(timezone=True), server_default=func.now())


class SystemEvent(Base):
    """
    Centralized event table for all system alerts/logs.
    """

    __tablename__ = "events"

    id = Column(Integer, primary_key=True, index=True)
    event_type = Column(
        String, index=True, nullable=False
    )  # e.g. 'Attendance', 'EquipmentDetection'
    camera_id = Column(Integer, ForeignKey("cameras.id"), nullable=True)
    camera_name = Column(String, nullable=True)
    confidence = Column(Float, nullable=True)
    snapshot_path = Column(String, nullable=True)
    timestamp = Column(DateTime(timezone=True), server_default=func.now())
    details = Column(String, nullable=True)  # JSON string for extra info


class SecurityAlert(Base):
    __tablename__ = "security_alerts"

    id = Column(Integer, primary_key=True, index=True)
    rule_name = Column(String, index=True)
    severity = Column(String, default="medium")
    camera_id = Column(Integer, ForeignKey("cameras.id"), nullable=True)
    details = Column(Text, nullable=True)
    timestamp = Column(DateTime(timezone=True), server_default=func.now())
    resolved = Column(Boolean, default=False)

    camera = relationship("Camera", back_populates="security_alerts")


class SecurityRule(Base):
    """
    Dynamic natural language rules evaluated by Gemini.
    """

    __tablename__ = "security_rules"

    id = Column(Integer, primary_key=True, index=True)
    target_area = Column(
        String, index=True, nullable=True
    )  # e.g., "ICU", "Surgical Ward", or "Global"
    rule_text = Column(String, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    is_active = Column(Boolean, default=True, nullable=False)


# ── AI / RAG Tables ────────────────────────────────────────


class KnowledgeDocument(Base):
    """
    Stores metadata for RAG documents (WHO Guidelines, SOPs).
    """

    __tablename__ = "knowledge_documents"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String, nullable=False)
    document_type = Column(String, nullable=False)  # e.g. 'SOP', 'GUIDELINE', 'MANUAL'
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    chunks = relationship(
        "DocumentChunk", back_populates="document", cascade="all, delete-orphan"
    )


class DocumentChunk(Base):
    """
    Stores semantic chunks with pgvector embeddings for RAG.
    """

    __tablename__ = "document_chunks"

    id = Column(Integer, primary_key=True, index=True)
    document_id = Column(Integer, ForeignKey("knowledge_documents.id"), nullable=False)
    content = Column(Text, nullable=False)
    embedding = Column(
        Vector(512), nullable=True
    )  # Dimension matching our embedding model
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    document = relationship("KnowledgeDocument", back_populates="chunks")


class MedicalFAQ(Base):
    """
    Stores verified frequently asked questions.
    """

    __tablename__ = "medical_faq"

    id = Column(Integer, primary_key=True, index=True)
    question = Column(String, nullable=False)
    answer = Column(Text, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class ConversationHistory(Base):
    """
    Stores user conversations for history, not used directly as LLM memory.
    """

    __tablename__ = "conversation_history"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer, ForeignKey("users.id"), nullable=True
    )  # Optional link to user
    session_id = Column(String, index=True, nullable=False)
    role = Column(String, nullable=False)  # 'user' or 'assistant'
    content = Column(Text, nullable=False)
    timestamp = Column(DateTime(timezone=True), server_default=func.now())


class AgentMemory(Base):
    """
    Long-term ChatGPT-style memory for learning facts about the user or session.
    """

    __tablename__ = "agent_memory"

    id = Column(Integer, primary_key=True, index=True)
    session_id = Column(String, index=True, nullable=False)
    fact = Column(Text, nullable=False)
    embedding = Column(
        Vector(384), nullable=True
    )  # all-MiniLM-L6-v2 (services/retrieval/vector_retriever.py) - 384 dims
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class LLMAuditLog(Base):
    """
    Logging of LLM prompts and responses for debugging and auditing.
    """

    __tablename__ = "llm_audit_log"

    id = Column(Integer, primary_key=True, index=True)
    session_id = Column(String, index=True, nullable=True)
    prompt = Column(Text, nullable=True)
    context_used = Column(Text, nullable=True)
    retrieved_rows = Column(Integer, nullable=True)
    model_used = Column(String, nullable=True)
    response = Column(Text, nullable=True)
    confidence = Column(Float, nullable=True)
    latency_ms = Column(Float, nullable=True)
    token_usage = Column(Integer, nullable=True)
    timestamp = Column(DateTime(timezone=True), server_default=func.now())


class PersonVerification(Base):
    """
    Stores PPE compliance verification tokens.
    A person verified in a verification zone receives a token that is valid
    across all cameras until it expires. This avoids repeated PPE checks.
    """

    __tablename__ = "person_verifications"

    id = Column(Integer, primary_key=True, index=True)
    staff_name = Column(String, index=True, nullable=False)
    camera_id = Column(Integer, ForeignKey("cameras.id"), nullable=True)
    has_mask = Column(Boolean, default=False)
    has_left_glove = Column(Boolean, default=False)
    has_right_glove = Column(Boolean, default=False)
    is_verified = Column(Boolean, default=False)
    confidence = Column(Float, nullable=True)
    verified_at = Column(DateTime(timezone=True), nullable=True)
    expires_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class SiteConfig(Base):
    """
    Singleton table storing hospital-wide branding configuration.
    Only one row (id=1) should ever exist.
    """

    __tablename__ = "site_config"

    id = Column(Integer, primary_key=True, default=1)
    hospital_name = Column(String, nullable=False, default="Hospital AI")
    agent_name = Column(String, nullable=False, default="AI")
    logo_path = Column(String, nullable=True)  # relative path under uploads/
    updated_at = Column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
