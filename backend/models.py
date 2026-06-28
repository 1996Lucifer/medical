from sqlalchemy import Column, Integer, String, Text, DateTime, Float, Date, ForeignKey, Boolean
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from pgvector.sqlalchemy import Vector
from database import Base
import datetime


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

    patient = relationship("Patient", back_populates="consultations")

    @property
    def patient_name(self):
        return self.patient.name if self.patient else None


class MedicalReport(Base):
    __tablename__ = "medical_reports"

    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id"), nullable=False)
    date = Column(DateTime(timezone=True), server_default=func.now())
    key_findings = Column(Text, nullable=True)
    abnormalities = Column(Text, nullable=True)
    recommendations = Column(Text, nullable=True)
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
    embedding = Column(Vector(512))  # Primary (first) photo embedding
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
    label = Column(String, nullable=True)   # e.g. "front", "left", "right", "angled"
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    staff = relationship("Staff", back_populates="photos")


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
    is_restricted = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    security_alerts = relationship("SecurityAlert", back_populates="camera")


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
    staff_id    = Column(Integer, ForeignKey("staff.id"), nullable=True)
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
    rule_name = Column(String(100), nullable=False)
    severity = Column(String(50), nullable=False, default="high")
    camera_id = Column(Integer, ForeignKey("cameras.id", ondelete="SET NULL"), nullable=True)
    details = Column(String, nullable=True) # JSON string for extra info
    timestamp = Column(DateTime(timezone=True), default=func.now())
    resolved = Column(Boolean, default=False, nullable=False)

    camera = relationship("Camera", back_populates="security_alerts")
