-- =============================================================================
-- Medical Agent — Full Database Schema
-- =============================================================================
-- Run this file once to bootstrap the database from scratch.
-- If the DB already exists, skip CREATE DATABASE and just run the rest.
--
-- psql usage:
--   psql -U postgres -f schema.sql
-- Or in psql interactive shell:
--   \i /path/to/schema.sql
-- =============================================================================


-- ── Step 1: Create database ───────────────────────────────────────────────────
-- Comment this out if the DB already exists.
CREATE DATABASE medical_agent;

-- Switch into the new database (psql only — comment out for other editors)
\c medical_agent


-- ── Step 2: Enable extensions ─────────────────────────────────────────────────
-- pgvector is required for face-embedding similarity search.
CREATE EXTENSION IF NOT EXISTS vector;


-- ── Step 3: Tables ────────────────────────────────────────────────────────────

-- Consultations
-- Stores patient audio consultation transcripts and AI-generated discharge summaries.
CREATE TABLE IF NOT EXISTS consultations (
    id                SERIAL PRIMARY KEY,
    patient_name      VARCHAR(255),
    date              TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    transcript        TEXT,
    discharge_summary TEXT
);

CREATE INDEX IF NOT EXISTS ix_consultations_id           ON consultations (id);
CREATE INDEX IF NOT EXISTS ix_consultations_patient_name ON consultations (patient_name);


-- Staff
-- Registered staff members with their 512-dimensional ArcFace embeddings.
-- The embedding column uses pgvector for fast cosine-similarity lookups.
CREATE TABLE IF NOT EXISTS staff (
    id         SERIAL PRIMARY KEY,
    name       VARCHAR(255)       NOT NULL,
    embedding  vector(512),                    -- InsightFace ArcFace 512-D (primary photo)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS ix_staff_id   ON staff (id);
CREATE INDEX IF NOT EXISTS ix_staff_name ON staff (name);


-- Staff Photos
-- One-to-many: each staff member can have multiple face photos (front, left, right, angled, etc.)
-- All embeddings are checked during recognition — more photos = better angle coverage.
CREATE TABLE IF NOT EXISTS staff_photos (
    id         SERIAL PRIMARY KEY,
    staff_id   INTEGER NOT NULL REFERENCES staff (id) ON DELETE CASCADE,
    embedding  vector(512) NOT NULL,
    label      VARCHAR(100),                   -- e.g. 'front', 'left', 'right', 'with glasses'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS ix_staff_photos_id       ON staff_photos (id);
CREATE INDEX IF NOT EXISTS ix_staff_photos_staff_id ON staff_photos (staff_id);


-- Attendance
-- Auto-marked when a registered staff member's face is recognised by the camera.
-- Duplicate entries are suppressed in application code (5-minute cooldown per person).
CREATE TABLE IF NOT EXISTS attendance (
    id         SERIAL PRIMARY KEY,
    staff_id   INTEGER REFERENCES staff (id) ON DELETE SET NULL,
    staff_name VARCHAR(255) NOT NULL,
    confidence FLOAT        NOT NULL,           -- cosine similarity score (0.0–1.0)
    timestamp  TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    date       DATE         NOT NULL DEFAULT CURRENT_DATE
);

CREATE INDEX IF NOT EXISTS ix_attendance_id         ON attendance (id);
CREATE INDEX IF NOT EXISTS ix_attendance_staff_name ON attendance (staff_name);
CREATE INDEX IF NOT EXISTS ix_attendance_date       ON attendance (date);


-- Cameras
CREATE TABLE IF NOT EXISTS cameras (
    id            SERIAL PRIMARY KEY,
    name          VARCHAR(255)  NOT NULL,
    location      VARCHAR(255),
    rtsp_url      VARCHAR(1024) NOT NULL,
    is_restricted BOOLEAN       NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS ix_cameras_id ON cameras (id);


-- Camera ROIs
CREATE TABLE IF NOT EXISTS camera_rois (
    id SERIAL PRIMARY KEY,
    camera_id INTEGER NOT NULL REFERENCES cameras (id) ON DELETE CASCADE,
    zone_name VARCHAR(255) NOT NULL,
    points TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_camera_rois_id ON camera_rois (id);
CREATE INDEX IF NOT EXISTS ix_camera_rois_zone_name ON camera_rois (zone_name);


-- Security Alerts
CREATE TABLE IF NOT EXISTS security_alerts (
    id SERIAL PRIMARY KEY,
    rule_name VARCHAR NOT NULL,
    severity VARCHAR DEFAULT 'medium',
    camera_id INTEGER REFERENCES cameras(id),
    details TEXT,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    resolved BOOLEAN DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS security_rules (
    id SERIAL PRIMARY KEY,
    target_area VARCHAR,
    rule_text VARCHAR NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE
);

CREATE INDEX IF NOT EXISTS ix_security_alerts_id ON security_alerts (id);


-- Equipment Types
CREATE TABLE IF NOT EXISTS equipment_types (
    id   SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE
);

CREATE INDEX IF NOT EXISTS ix_equipment_types_id   ON equipment_types (id);
CREATE INDEX IF NOT EXISTS ix_equipment_types_name ON equipment_types (name);


-- Equipment Items
CREATE TABLE IF NOT EXISTS equipment_items (
    id               SERIAL PRIMARY KEY,
    equipment_id     VARCHAR(255) NOT NULL UNIQUE,
    type_id          INTEGER NOT NULL REFERENCES equipment_types (id) ON DELETE CASCADE,
    current_location VARCHAR(255),
    last_seen        TIMESTAMP WITH TIME ZONE
);

CREATE INDEX IF NOT EXISTS ix_equipment_items_id           ON equipment_items (id);
CREATE INDEX IF NOT EXISTS ix_equipment_items_equipment_id ON equipment_items (equipment_id);


-- Equipment Tracking
CREATE TABLE IF NOT EXISTS equipment_tracking (
    id                SERIAL PRIMARY KEY,
    equipment_item_id INTEGER NOT NULL REFERENCES equipment_items (id) ON DELETE CASCADE,
    camera_id         INTEGER REFERENCES cameras (id) ON DELETE SET NULL,
    camera_name       VARCHAR(255),
    timestamp         TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS ix_equipment_tracking_id ON equipment_tracking (id);


-- Events
CREATE TABLE IF NOT EXISTS events (
    id            SERIAL PRIMARY KEY,
    event_type    VARCHAR(100) NOT NULL,
    camera_id     INTEGER REFERENCES cameras (id) ON DELETE SET NULL,
    camera_name   VARCHAR(255),
    confidence    FLOAT,
    snapshot_path VARCHAR(255),
    timestamp     TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    details       TEXT
);

CREATE INDEX IF NOT EXISTS ix_events_id         ON events (id);
CREATE INDEX IF NOT EXISTS ix_events_event_type ON events (event_type);

CREATE INDEX IF NOT EXISTS ix_inventory_alerts_timestamp ON inventory_alerts (timestamp);
CREATE INDEX IF NOT EXISTS ix_inventory_alerts_resolved  ON inventory_alerts (resolved);

-- ── RBAC System ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rbac_groups (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT
);
CREATE INDEX IF NOT EXISTS ix_rbac_groups_name ON rbac_groups (name);

CREATE TABLE IF NOT EXISTS rbac_permissions (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT
);
CREATE INDEX IF NOT EXISTS ix_rbac_permissions_name ON rbac_permissions (name);

CREATE TABLE IF NOT EXISTS user_groups (
    user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    group_id INTEGER NOT NULL REFERENCES rbac_groups (id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, group_id)
);

CREATE TABLE IF NOT EXISTS group_permissions (
    group_id INTEGER NOT NULL REFERENCES rbac_groups (id) ON DELETE CASCADE,
    permission_id INTEGER NOT NULL REFERENCES rbac_permissions (id) ON DELETE CASCADE,
    PRIMARY KEY (group_id, permission_id)
);

CREATE TABLE IF NOT EXISTS user_permissions (
    user_id INTEGER NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    permission_id INTEGER NOT NULL REFERENCES rbac_permissions (id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, permission_id)
);


-- =============================================================================
-- Useful read-only queries for your DB editor
-- =============================================================================

-- View today's attendance with staff details:
-- SELECT a.id, a.staff_name, s.name AS registered_name,
--        ROUND((a.confidence * 100)::numeric, 1) AS match_pct,
--        a.timestamp::time AS checked_in_at
-- FROM   attendance a
-- LEFT   JOIN staff s ON s.id = a.staff_id
-- WHERE  a.date = CURRENT_DATE
-- ORDER  BY a.timestamp DESC;

-- Count of attendances per staff member for today:
-- SELECT staff_name, COUNT(*) AS times_seen,
--        MAX(timestamp) AS last_seen,
--        ROUND(AVG(confidence * 100)::numeric, 1) AS avg_match_pct
-- FROM   attendance
-- WHERE  date = CURRENT_DATE
-- GROUP  BY staff_name
-- ORDER  BY last_seen DESC;

-- List all staff with their registration date:
-- SELECT id, name, created_at FROM staff ORDER BY created_at DESC;

-- List all consultations (latest first):
-- SELECT id, patient_name, date, LEFT(transcript, 120) AS transcript_preview
-- FROM   consultations
-- ORDER  BY date DESC;
