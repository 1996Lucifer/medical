-- =============================================================================
-- Medical Agent — Full Database Schema
-- =============================================================================
-- Enable Extensions
CREATE EXTENSION IF NOT EXISTS vector;

-- RBAC & User Management
CREATE TABLE IF NOT EXISTS users (
    id              SERIAL PRIMARY KEY,
    username        VARCHAR(255) UNIQUE NOT NULL,
    hashed_password VARCHAR(255) NOT NULL,
    role            VARCHAR(50) NOT NULL DEFAULT 'admin',
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_users_id ON users (id);
CREATE INDEX IF NOT EXISTS ix_users_username ON users (username);

CREATE TABLE IF NOT EXISTS rbac_groups (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(255) UNIQUE NOT NULL,
    description TEXT
);
CREATE INDEX IF NOT EXISTS ix_rbac_groups_id ON rbac_groups (id);
CREATE INDEX IF NOT EXISTS ix_rbac_groups_name ON rbac_groups (name);

CREATE TABLE IF NOT EXISTS rbac_permissions (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(255) UNIQUE NOT NULL,
    description TEXT
);
CREATE INDEX IF NOT EXISTS ix_rbac_permissions_id ON rbac_permissions (id);
CREATE INDEX IF NOT EXISTS ix_rbac_permissions_name ON rbac_permissions (name);

CREATE TABLE IF NOT EXISTS user_groups (
    user_id  INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    group_id INTEGER NOT NULL REFERENCES rbac_groups (id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, group_id)
);

CREATE TABLE IF NOT EXISTS group_permissions (
    group_id      INTEGER NOT NULL REFERENCES rbac_groups (id) ON DELETE CASCADE,
    permission_id INTEGER NOT NULL REFERENCES rbac_permissions (id) ON DELETE CASCADE,
    PRIMARY KEY (group_id, permission_id)
);

CREATE TABLE IF NOT EXISTS user_permissions (
    user_id       INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    permission_id INTEGER NOT NULL REFERENCES rbac_permissions (id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, permission_id)
);

-- Patients & Consultations
CREATE TABLE IF NOT EXISTS patients (
    id         SERIAL PRIMARY KEY,
    name       VARCHAR(255) NOT NULL,
    mrn        VARCHAR(100) UNIQUE,
    dob        DATE,
    gender     VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_patients_id ON patients (id);
CREATE INDEX IF NOT EXISTS ix_patients_name ON patients (name);
CREATE INDEX IF NOT EXISTS ix_patients_mrn ON patients (mrn);

CREATE TABLE IF NOT EXISTS consultations (
    id                SERIAL PRIMARY KEY,
    patient_id        INTEGER NOT NULL REFERENCES patients (id) ON DELETE CASCADE,
    date              TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    transcript        TEXT,
    discharge_summary TEXT,
    prescription      TEXT
);
CREATE INDEX IF NOT EXISTS ix_consultations_id ON consultations (id);

CREATE TABLE IF NOT EXISTS medical_reports (
    id               SERIAL PRIMARY KEY,
    patient_id       INTEGER NOT NULL REFERENCES patients (id) ON DELETE CASCADE,
    date             TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    file_path        VARCHAR(1024),
    key_findings     TEXT,
    abnormalities    TEXT,
    recommendations  TEXT,
    vitals_extracted TEXT,
    raw_response     TEXT
);
CREATE INDEX IF NOT EXISTS ix_medical_reports_id ON medical_reports (id);

-- Staff Recognition & Biometrics
CREATE TABLE IF NOT EXISTS staff (
    id              SERIAL PRIMARY KEY,
    name            VARCHAR(255) NOT NULL,
    role            VARCHAR(100) DEFAULT 'Medical Staff',
    embedding       vector(512),
    upper_embedding vector(512),
    photo_path      VARCHAR(1024),
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_staff_id ON staff (id);
CREATE INDEX IF NOT EXISTS ix_staff_name ON staff (name);

CREATE TABLE IF NOT EXISTS staff_photos (
    id              SERIAL PRIMARY KEY,
    staff_id        INTEGER NOT NULL REFERENCES staff (id) ON DELETE CASCADE,
    embedding       vector(512) NOT NULL,
    upper_embedding vector(512),
    label           VARCHAR(100),
    photo_path      VARCHAR(1024),
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_staff_photos_id ON staff_photos (id);
CREATE INDEX IF NOT EXISTS ix_staff_photos_staff_id ON staff_photos (staff_id);

CREATE TABLE IF NOT EXISTS staff_activity (
    id         SERIAL PRIMARY KEY,
    title      VARCHAR(255) NOT NULL,
    subtitle   VARCHAR(255) NOT NULL,
    color      VARCHAR(50) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_staff_activity_id ON staff_activity (id);

-- Cameras, ROIs, and Attendance
CREATE TABLE IF NOT EXISTS cameras (
    id            SERIAL PRIMARY KEY,
    name          VARCHAR(255) NOT NULL,
    location      VARCHAR(255),
    rtsp_url      VARCHAR(1024) NOT NULL,
    ha_entity_id  VARCHAR(255),
    is_restricted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_cameras_id ON cameras (id);

CREATE TABLE IF NOT EXISTS camera_rois (
    id        SERIAL PRIMARY KEY,
    camera_id INTEGER NOT NULL REFERENCES cameras (id) ON DELETE CASCADE,
    zone_name VARCHAR(255) NOT NULL,
    zone_type VARCHAR(50) NOT NULL DEFAULT 'observation',
    points    TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_camera_rois_id ON camera_rois (id);
CREATE INDEX IF NOT EXISTS ix_camera_rois_zone_name ON camera_rois (zone_name);

CREATE TABLE IF NOT EXISTS attendance (
    id          SERIAL PRIMARY KEY,
    staff_id    INTEGER REFERENCES staff (id) ON DELETE SET NULL,
    staff_name  VARCHAR(255) NOT NULL,
    confidence  FLOAT NOT NULL,
    date        DATE NOT NULL DEFAULT CURRENT_DATE,
    entry_time  TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_seen   TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    exit_time   TIMESTAMP WITH TIME ZONE,
    camera_id   INTEGER REFERENCES cameras (id) ON DELETE SET NULL,
    camera_name VARCHAR(255)
);
CREATE INDEX IF NOT EXISTS ix_attendance_id ON attendance (id);
CREATE INDEX IF NOT EXISTS ix_attendance_staff_name ON attendance (staff_name);
CREATE INDEX IF NOT EXISTS ix_attendance_date ON attendance (date);

-- Equipment Tracking & Inventory
CREATE TABLE IF NOT EXISTS equipment_types (
    id   SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE
);
CREATE INDEX IF NOT EXISTS ix_equipment_types_id ON equipment_types (id);
CREATE INDEX IF NOT EXISTS ix_equipment_types_name ON equipment_types (name);

CREATE TABLE IF NOT EXISTS equipment_items (
    id               SERIAL PRIMARY KEY,
    equipment_id     VARCHAR(255) NOT NULL UNIQUE,
    type_id          INTEGER NOT NULL REFERENCES equipment_types (id) ON DELETE CASCADE,
    current_location VARCHAR(255),
    last_seen        TIMESTAMP WITH TIME ZONE
);
CREATE INDEX IF NOT EXISTS ix_equipment_items_id ON equipment_items (id);
CREATE INDEX IF NOT EXISTS ix_equipment_items_equipment_id ON equipment_items (equipment_id);

CREATE TABLE IF NOT EXISTS equipment_tracking (
    id                SERIAL PRIMARY KEY,
    equipment_item_id INTEGER NOT NULL REFERENCES equipment_items (id) ON DELETE CASCADE,
    camera_id         INTEGER REFERENCES cameras (id) ON DELETE SET NULL,
    camera_name       VARCHAR(255),
    timestamp         TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_equipment_tracking_id ON equipment_tracking (id);

-- Events, Alerts, & Verification Tokens
CREATE TABLE IF NOT EXISTS events (
    id            SERIAL PRIMARY KEY,
    event_type    VARCHAR(100) NOT NULL,
    camera_id     INTEGER REFERENCES cameras (id) ON DELETE SET NULL,
    camera_name   VARCHAR(255),
    confidence    FLOAT,
    snapshot_path VARCHAR(1024),
    timestamp     TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    details       TEXT
);
CREATE INDEX IF NOT EXISTS ix_events_id ON events (id);
CREATE INDEX IF NOT EXISTS ix_events_event_type ON events (event_type);

CREATE TABLE IF NOT EXISTS security_alerts (
    id        SERIAL PRIMARY KEY,
    rule_name VARCHAR(255) NOT NULL,
    severity  VARCHAR(50) DEFAULT 'medium',
    camera_id INTEGER REFERENCES cameras (id) ON DELETE SET NULL,
    details   TEXT,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    resolved  BOOLEAN DEFAULT FALSE
);
CREATE INDEX IF NOT EXISTS ix_security_alerts_id ON security_alerts (id);

CREATE TABLE IF NOT EXISTS security_rules (
    id          SERIAL PRIMARY KEY,
    target_area VARCHAR(255),
    rule_text   TEXT NOT NULL,
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE INDEX IF NOT EXISTS ix_security_rules_id ON security_rules (id);
CREATE INDEX IF NOT EXISTS ix_security_rules_target_area ON security_rules (target_area);

CREATE TABLE IF NOT EXISTS person_verifications (
    id              SERIAL PRIMARY KEY,
    staff_name      VARCHAR(255) NOT NULL,
    camera_id       INTEGER REFERENCES cameras (id) ON DELETE SET NULL,
    has_mask        BOOLEAN DEFAULT FALSE,
    has_left_glove  BOOLEAN DEFAULT FALSE,
    has_right_glove BOOLEAN DEFAULT FALSE,
    is_verified     BOOLEAN DEFAULT FALSE,
    confidence      FLOAT,
    verified_at     TIMESTAMP WITH TIME ZONE,
    expires_at      TIMESTAMP WITH TIME ZONE,
    created_at      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_person_verifications_id ON person_verifications (id);
CREATE INDEX IF NOT EXISTS ix_person_verifications_staff_name ON person_verifications (staff_name);

-- AI, RAG & Memory Tables
CREATE TABLE IF NOT EXISTS knowledge_documents (
    id            SERIAL PRIMARY KEY,
    title         VARCHAR(255) NOT NULL,
    document_type VARCHAR(100) NOT NULL,
    created_at    TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_knowledge_documents_id ON knowledge_documents (id);

CREATE TABLE IF NOT EXISTS document_chunks (
    id          SERIAL PRIMARY KEY,
    document_id INTEGER NOT NULL REFERENCES knowledge_documents (id) ON DELETE CASCADE,
    content     TEXT NOT NULL,
    embedding   vector(512),
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_document_chunks_id ON document_chunks (id);

CREATE TABLE IF NOT EXISTS medical_faq (
    id         SERIAL PRIMARY KEY,
    question   TEXT NOT NULL,
    answer     TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_medical_faq_id ON medical_faq (id);

CREATE TABLE IF NOT EXISTS conversation_history (
    id         SERIAL PRIMARY KEY,
    user_id    INTEGER REFERENCES users (id) ON DELETE SET NULL,
    session_id VARCHAR(255) NOT NULL,
    role       VARCHAR(50) NOT NULL,
    content    TEXT NOT NULL,
    timestamp  TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_conversation_history_id ON conversation_history (id);
CREATE INDEX IF NOT EXISTS ix_conversation_history_session_id ON conversation_history (session_id);

CREATE TABLE IF NOT EXISTS agent_memory (
    id         SERIAL PRIMARY KEY,
    session_id VARCHAR(255) NOT NULL,
    fact       TEXT NOT NULL,
    embedding  vector(512),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_agent_memory_id ON agent_memory (id);
CREATE INDEX IF NOT EXISTS ix_agent_memory_session_id ON agent_memory (session_id);

CREATE TABLE IF NOT EXISTS llm_audit_log (
    id             SERIAL PRIMARY KEY,
    session_id     VARCHAR(255),
    prompt         TEXT,
    context_used   TEXT,
    retrieved_rows INTEGER,
    model_used     VARCHAR(255),
    response       TEXT,
    confidence     FLOAT,
    latency_ms     FLOAT,
    token_usage    INTEGER,
    timestamp      TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS ix_llm_audit_log_id ON llm_audit_log (id);
CREATE INDEX IF NOT EXISTS ix_llm_audit_log_session_id ON llm_audit_log (session_id);
