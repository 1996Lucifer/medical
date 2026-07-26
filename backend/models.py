from sqlalchemy import Column, Integer, String, Text, DateTime, Float, Date, ForeignKey, Boolean, Table
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from pgvector.sqlalchemy import Vector
from database import Base
import datetime

# ── RBAC Association Tables ────────────────────────────────────────
user_groups = Table(
    'user_groups',
    Base.metadata,
    Column('user_id', Integer, ForeignKey('users.id'), primary_key=True),
    Column('group_id', Integer, ForeignKey('rbac_groups.id'), primary_key=True)
)

group_permissions = Table(
    'group_permissions',
    Base.metadata,
    Column('group_id', Integer, ForeignKey('rbac_groups.id'), primary_key=True),
    Column('permission_id', Integer, ForeignKey('rbac_permissions.id'), primary_key=True)
)

user_permissions = Table(
    'user_permissions',
    Base.metadata,
    Column('user_id', Integer, ForeignKey('users.id'), primary_key=True),
    Column('permission_id', Integer, ForeignKey('rbac_permissions.id'), primary_key=True)
)

class RBACGroup(Base):
    __tablename__ = "rbac_groups"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, index=True, nullable=False)
    description = Column(String, nullable=True)

    users = relationship("User", secondary=user_groups, back_populates="groups")
    permissions = relationship("RBACPermission", secondary=group_permissions, back_populates="groups")

class RBACPermission(Base):
    __tablename__ = "rbac_permissions"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, index=True, nullable=False)
    description = Column(String, nullable=True)

    groups = relationship("RBACGroup", secondary=group_permissions, back_populates="permissions")
    users = relationship("User", secondary=user_permissions, back_populates="direct_permissions")

class User(Base):
    """
    Admin user for Role-Based Access Control (RBAC).
    """
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    role = Column(String, nullable=False, default="admin")
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    groups = relationship("RBACGroup", secondary=user_groups, back_populates="users")
    direct_permissions = relationship("RBACPermission", secondary=user_permissions, back_populates="users")


class Patient(Base):
    """
    Centralized Patient record for scalability.
    """
    __tablename__ = "patients"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, index=True, nullable=False)
    mrn = Column(String, unique=True, index=True, nullable=True) # Medical Record Number
    dob = Column(Date, nullable=True)
    gender = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    consultations = relationship("Consultation", back_populates="patient", cascade="all, delete-orphan")
    medical_reports = relationship("MedicalReport", back_populates="patient", cascade="all, delete-orphan")


class Consultation(Base):
    __tablename__ = "consultations"

    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id"), nullable=False)
    date = Column(DateTime(timezone=True), server_default=func.now())
    transcript = Column(Text, nullable=True)
    discharge_summary = Column(Text, nullable=True)
    prescription = Column(Text, nullable=True)

    patient = relationship("Patient", back_populates="consultations")

    @property
    def patient_name(self):
        return self.patient.name if self.patient else None


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
    role = Column(String, nullable=True, default='Medical Staff')
    embedding = Column(Vector(512))  # Primary (first) photo embedding
    upper_embedding = Column(Vector(512), nullable=True) # Upper 45% mask tracking embedding
    photo_path = Column(String, nullable=True) # Path to the saved photo file
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    # Additional photos for multi-angle recognition
    photos = relationship("StaffPhoto", back_populates="staff",
                          cascade="all, delete-orphan")


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
    label = Column(String, nullable=True)   # e.g. "front", "left", "right", "angled"
    photo_path = Column(String, nullable=True) # Path to the saved photo file
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    staff = relationship("Staff", back_populates="photos")

class StaffActivity(Base):
    __tablename__ = "staff_activity"
    id = Column(Integer, primary_key=True, index=True)
    title = Column(String, nullable=False)
    subtitle = Column(String, nullable=False)
    color = Column(String, nullable=False) # e.g. "green", "orange", "red"
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class Camera(Base):
    """
    A registered RTSP camera with a human-readable name and location.
    Attendance records are linked to the camera that detected the person.
    """
    __tablename__ = "cameras"

    id         = Column(Integer, primary_key=True, index=True)
    name       = Column(String, nullable=False)     # e.g. "Main Entrance"
    location   = Column(String, nullable=True)      # e.g. "Ground Floor, Block A"
    rtsp_url   = Column(String, nullable=False)
    ha_entity_id = Column(String, nullable=True)    # e.g. "siren.tapo_camera_alarm"
    is_restricted = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    security_alerts = relationship("SecurityAlert", back_populates="camera")
    rois = relationship("CameraROI", back_populates="camera", cascade="all, delete-orphan")


class CameraROI(Base):
    """
    Region of Interest (ROI) mapping for a specific camera.
    points: JSON array of normalized coordinates, e.g., [{"x": 0.1, "y": 0.2}, ...]
    zone_type: 'observation', 'verification', or 'restricted'
    """
    __tablename__ = "camera_rois"

    id = Column(Integer, primary_key=True, index=True)
    camera_id = Column(Integer, ForeignKey("cameras.id"), nullable=False)
    zone_name = Column(String, index=True, nullable=False) # e.g. 'ICU', 'Operating Room'
    zone_type = Column(String, nullable=False, default="observation")  # observation | verification | restricted
    points = Column(Text, nullable=False) # JSON array

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

    id          = Column(Integer, primary_key=True, index=True)
    staff_id    = Column(Integer, ForeignKey("staff.id", ondelete="SET NULL"), nullable=True)
    staff_name  = Column(String, index=True, nullable=False)
    confidence  = Column(Float, nullable=False)          # best score at entry
    date        = Column(Date, nullable=False, default=datetime.date.today)
    entry_time  = Column(DateTime(timezone=True), server_default=func.now())
    last_seen   = Column(DateTime(timezone=True), server_default=func.now(), nullable=True)
    exit_time   = Column(DateTime(timezone=True), nullable=True)  # manual checkout
    camera_id   = Column(Integer, ForeignKey("cameras.id"), nullable=True)
    camera_name = Column(String, nullable=True)          # e.g. "Main Entrance"


class EquipmentType(Base):
    __tablename__ = "equipment_types"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, index=True, nullable=False)  # e.g. "Wheelchair", "Ventilator"


class EquipmentItem(Base):
    """
    Specific instance of equipment.
    """
    __tablename__ = "equipment_items"

    id = Column(Integer, primary_key=True, index=True)
    equipment_id = Column(String, unique=True, index=True, nullable=False) # e.g. "Wheelchair #12"
    type_id = Column(Integer, ForeignKey("equipment_types.id"), nullable=False)
    current_location = Column(String, nullable=True) # Last known location based on camera
    last_seen = Column(DateTime(timezone=True), nullable=True)
    
    # Optional relationship
    # type = relationship("EquipmentType")


class EquipmentTracking(Base):
    """
    Log of equipment movement.
    """
    __tablename__ = "equipment_tracking"

    id = Column(Integer, primary_key=True, index=True)
    equipment_item_id = Column(Integer, ForeignKey("equipment_items.id"), nullable=False)
    camera_id = Column(Integer, ForeignKey("cameras.id"), nullable=True)
    camera_name = Column(String, nullable=True)
    timestamp = Column(DateTime(timezone=True), server_default=func.now())


class SystemEvent(Base):
    """
    Centralized event table for all system alerts/logs.
    """
    __tablename__ = "events"

    id = Column(Integer, primary_key=True, index=True)
    event_type = Column(String, index=True, nullable=False) # e.g. 'Attendance', 'EquipmentDetection'
    camera_id = Column(Integer, ForeignKey("cameras.id"), nullable=True)
    camera_name = Column(String, nullable=True)
    confidence = Column(Float, nullable=True)
    snapshot_path = Column(String, nullable=True)
    timestamp = Column(DateTime(timezone=True), server_default=func.now())
    details = Column(String, nullable=True) # JSON string for extra info


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
    target_area = Column(String, index=True, nullable=True) # e.g., "ICU", "Surgical Ward", or "Global"
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
    document_type = Column(String, nullable=False) # e.g. 'SOP', 'GUIDELINE', 'MANUAL'
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    chunks = relationship("DocumentChunk", back_populates="document", cascade="all, delete-orphan")


class DocumentChunk(Base):
    """
    Stores semantic chunks with pgvector embeddings for RAG.
    """
    __tablename__ = "document_chunks"

    id = Column(Integer, primary_key=True, index=True)
    document_id = Column(Integer, ForeignKey("knowledge_documents.id"), nullable=False)
    content = Column(Text, nullable=False)
    embedding = Column(Vector(512), nullable=True) # Dimension matching our embedding model
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
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True) # Optional link to user
    session_id = Column(String, index=True, nullable=False)
    role = Column(String, nullable=False) # 'user' or 'assistant'
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
    embedding = Column(Vector(512), nullable=True) # Assuming 512 for our embedding model
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

