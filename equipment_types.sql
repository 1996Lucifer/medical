-- -------------------------------------------------------------
-- TablePlus 26.7.2(738)
--
-- https://tableplus.com/
--
-- Database: medical_agent
-- Generation Time: 2026-07-11 22:56:44.7080
-- -------------------------------------------------------------


-- Sequence and defined type
CREATE SEQUENCE IF NOT EXISTS equipment_types_id_seq;

-- Table Definition
CREATE TABLE "public"."equipment_types" (
    "id" int4 NOT NULL DEFAULT nextval('equipment_types_id_seq'::regclass),
    "name" varchar NOT NULL,
    PRIMARY KEY ("id")
);

-- Sequence and defined type
CREATE SEQUENCE IF NOT EXISTS equipment_items_id_seq;

-- Table Definition
CREATE TABLE "public"."equipment_items" (
    "id" int4 NOT NULL DEFAULT nextval('equipment_items_id_seq'::regclass),
    "equipment_id" varchar NOT NULL,
    "type_id" int4 NOT NULL,
    "current_location" varchar,
    "last_seen" timestamptz,
    PRIMARY KEY ("id")
);

-- Sequence and defined type
CREATE SEQUENCE IF NOT EXISTS events_id_seq;

-- Table Definition
CREATE TABLE "public"."events" (
    "id" int4 NOT NULL DEFAULT nextval('events_id_seq'::regclass),
    "event_type" varchar NOT NULL,
    "camera_id" int4,
    "camera_name" varchar,
    "confidence" float8,
    "snapshot_path" varchar,
    "timestamp" timestamptz DEFAULT now(),
    "details" varchar,
    PRIMARY KEY ("id")
);

-- Sequence and defined type
CREATE SEQUENCE IF NOT EXISTS security_alerts_id_seq;

-- Table Definition
CREATE TABLE "public"."security_alerts" (
    "id" int4 NOT NULL DEFAULT nextval('security_alerts_id_seq'::regclass),
    "rule_name" varchar(100) NOT NULL,
    "severity" varchar(50) NOT NULL,
    "camera_id" int4,
    "details" varchar,
    "timestamp" timestamptz,
    "resolved" bool NOT NULL,
    PRIMARY KEY ("id")
);

-- Sequence and defined type
CREATE SEQUENCE IF NOT EXISTS security_rules_id_seq;

-- Table Definition
CREATE TABLE "public"."security_rules" (
    "id" int4 NOT NULL DEFAULT nextval('security_rules_id_seq'::regclass),
    "target_area" varchar,
    "rule_text" varchar NOT NULL,
    "created_at" timestamptz DEFAULT now(),
    "is_active" bool NOT NULL,
    PRIMARY KEY ("id")
);

-- Sequence and defined type
CREATE SEQUENCE IF NOT EXISTS equipment_tracking_id_seq;

-- Table Definition
CREATE TABLE "public"."equipment_tracking" (
    "id" int4 NOT NULL DEFAULT nextval('equipment_tracking_id_seq'::regclass),
    "equipment_item_id" int4 NOT NULL,
    "camera_id" int4,
    "camera_name" varchar,
    "timestamp" timestamptz DEFAULT now(),
    PRIMARY KEY ("id")
);

-- Sequence and defined type
CREATE SEQUENCE IF NOT EXISTS users_id_seq;

-- Table Definition
CREATE TABLE "public"."users" (
    "id" int4 NOT NULL DEFAULT nextval('users_id_seq'::regclass),
    "username" varchar NOT NULL,
    "hashed_password" varchar NOT NULL,
    "role" varchar NOT NULL,
    "created_at" timestamptz DEFAULT now(),
    PRIMARY KEY ("id")
);

-- Sequence and defined type
CREATE SEQUENCE IF NOT EXISTS cameras_id_seq;

-- Table Definition
CREATE TABLE "public"."cameras" (
    "id" int4 NOT NULL DEFAULT nextval('cameras_id_seq'::regclass),
    "name" varchar NOT NULL,
    "location" varchar,
    "ip_address" varchar NOT NULL DEFAULT '127.0.0.1',
    "port" int4 NOT NULL DEFAULT 554,
    "username" varchar,
    "password" varchar,
    "stream_path" varchar,
    "is_restricted" bool NOT NULL DEFAULT false,
    "created_at" timestamptz DEFAULT now(),
    PRIMARY KEY ("id")
);

-- Sequence and defined type
CREATE SEQUENCE IF NOT EXISTS patients_id_seq;

-- Table Definition
CREATE TABLE "public"."patients" (
    "id" int4 NOT NULL DEFAULT nextval('patients_id_seq'::regclass),
    "name" varchar NOT NULL,
    "mrn" varchar,
    "dob" date,
    "gender" varchar,
    "created_at" timestamptz DEFAULT now(),
    PRIMARY KEY ("id")
);

-- Sequence and defined type
CREATE SEQUENCE IF NOT EXISTS consultations_id_seq;

-- Table Definition
CREATE TABLE "public"."consultations" (
    "id" int4 NOT NULL DEFAULT nextval('consultations_id_seq'::regclass),
    "patient_id" int4 NOT NULL,
    "date" timestamptz DEFAULT now(),
    "transcript" text,
    "discharge_summary" text,
    PRIMARY KEY ("id")
);

-- Sequence and defined type
CREATE SEQUENCE IF NOT EXISTS medical_reports_id_seq;

-- Table Definition
CREATE TABLE "public"."medical_reports" (
    "id" int4 NOT NULL DEFAULT nextval('medical_reports_id_seq'::regclass),
    "patient_id" int4 NOT NULL,
    "date" timestamptz DEFAULT now(),
    "key_findings" text,
    "abnormalities" text,
    "recommendations" text,
    "raw_response" text,
    PRIMARY KEY ("id")
);

-- Sequence and defined type
CREATE SEQUENCE IF NOT EXISTS staff_id_seq;

-- Table Definition
CREATE TABLE "public"."staff" (
    "id" int4 NOT NULL DEFAULT nextval('staff_id_seq'::regclass),
    "name" varchar,
    "embedding" vector,
    "created_at" timestamptz DEFAULT now(),
    "photo_path" varchar,
    "upper_embedding" vector,
    PRIMARY KEY ("id")
);

-- Sequence and defined type
CREATE SEQUENCE IF NOT EXISTS staff_photos_id_seq;

-- Table Definition
CREATE TABLE "public"."staff_photos" (
    "id" int4 NOT NULL DEFAULT nextval('staff_photos_id_seq'::regclass),
    "staff_id" int4 NOT NULL,
    "embedding" vector NOT NULL,
    "label" varchar,
    "created_at" timestamptz DEFAULT now(),
    "photo_path" varchar,
    "upper_embedding" vector,
    PRIMARY KEY ("id")
);

-- Sequence and defined type
CREATE SEQUENCE IF NOT EXISTS attendance_id_seq;

-- Table Definition
CREATE TABLE "public"."attendance" (
    "id" int4 NOT NULL DEFAULT nextval('attendance_id_seq'::regclass),
    "staff_id" int4,
    "staff_name" varchar NOT NULL,
    "confidence" float8 NOT NULL,
    "date" date NOT NULL,
    "entry_time" timestamptz DEFAULT now(),
    "last_seen" timestamptz DEFAULT now(),
    "exit_time" timestamptz,
    "camera_id" int4,
    "camera_name" varchar,
    PRIMARY KEY ("id")
);

-- Table Definition
CREATE TABLE "public"."user_groups" (
    "user_id" int4 NOT NULL,
    "group_id" int4 NOT NULL,
    PRIMARY KEY ("user_id","group_id")
);

-- Sequence and defined type
CREATE SEQUENCE IF NOT EXISTS rbac_groups_id_seq;

-- Table Definition
CREATE TABLE "public"."rbac_groups" (
    "id" int4 NOT NULL DEFAULT nextval('rbac_groups_id_seq'::regclass),
    "name" varchar NOT NULL,
    "description" varchar,
    PRIMARY KEY ("id")
);

-- Table Definition
CREATE TABLE "public"."group_permissions" (
    "group_id" int4 NOT NULL,
    "permission_id" int4 NOT NULL,
    PRIMARY KEY ("group_id","permission_id")
);

-- Sequence and defined type
CREATE SEQUENCE IF NOT EXISTS rbac_permissions_id_seq;

-- Table Definition
CREATE TABLE "public"."rbac_permissions" (
    "id" int4 NOT NULL DEFAULT nextval('rbac_permissions_id_seq'::regclass),
    "name" varchar NOT NULL,
    "description" varchar,
    PRIMARY KEY ("id")
);

-- Table Definition
CREATE TABLE "public"."user_permissions" (
    "user_id" int4 NOT NULL,
    "permission_id" int4 NOT NULL,
    PRIMARY KEY ("user_id","permission_id")
);

-- Sequence and defined type
CREATE SEQUENCE IF NOT EXISTS medical_faq_id_seq;

-- Table Definition
CREATE TABLE "public"."medical_faq" (
    "id" int4 NOT NULL DEFAULT nextval('medical_faq_id_seq'::regclass),
    "question" varchar NOT NULL,
    "answer" text NOT NULL,
    "created_at" timestamptz DEFAULT now(),
    PRIMARY KEY ("id")
);

-- Sequence and defined type
CREATE SEQUENCE IF NOT EXISTS camera_rois_id_seq;

-- Table Definition
CREATE TABLE "public"."camera_rois" (
    "id" int4 NOT NULL DEFAULT nextval('camera_rois_id_seq'::regclass),
    "camera_id" int4 NOT NULL,
    "zone_name" varchar NOT NULL,
    "points" text NOT NULL,
    PRIMARY KEY ("id")
);

-- Sequence and defined type
CREATE SEQUENCE IF NOT EXISTS conversation_history_id_seq;

-- Table Definition
CREATE TABLE "public"."conversation_history" (
    "id" int4 NOT NULL DEFAULT nextval('conversation_history_id_seq'::regclass),
    "user_id" int4,
    "session_id" varchar NOT NULL,
    "role" varchar NOT NULL,
    "content" text NOT NULL,
    "timestamp" timestamptz DEFAULT now(),
    PRIMARY KEY ("id")
);

-- Sequence and defined type
CREATE SEQUENCE IF NOT EXISTS llm_audit_log_id_seq;

-- Table Definition
CREATE TABLE "public"."llm_audit_log" (
    "id" int4 NOT NULL DEFAULT nextval('llm_audit_log_id_seq'::regclass),
    "session_id" varchar,
    "prompt" text,
    "context_used" text,
    "retrieved_rows" int4,
    "model_used" varchar,
    "response" text,
    "confidence" float8,
    "latency_ms" float8,
    "token_usage" int4,
    "timestamp" timestamptz DEFAULT now(),
    PRIMARY KEY ("id")
);

-- Sequence and defined type
CREATE SEQUENCE IF NOT EXISTS knowledge_documents_id_seq;

-- Table Definition
CREATE TABLE "public"."knowledge_documents" (
    "id" int4 NOT NULL DEFAULT nextval('knowledge_documents_id_seq'::regclass),
    "title" varchar NOT NULL,
    "document_type" varchar NOT NULL,
    "created_at" timestamptz DEFAULT now(),
    PRIMARY KEY ("id")
);

-- Sequence and defined type
CREATE SEQUENCE IF NOT EXISTS document_chunks_id_seq;

-- Table Definition
CREATE TABLE "public"."document_chunks" (
    "id" int4 NOT NULL DEFAULT nextval('document_chunks_id_seq'::regclass),
    "document_id" int4 NOT NULL,
    "content" text NOT NULL,
    "embedding" vector,
    "created_at" timestamptz DEFAULT now(),
    PRIMARY KEY ("id")
);



-- Indices
CREATE UNIQUE INDEX ix_equipment_types_name ON public.equipment_types USING btree (name);
CREATE INDEX ix_equipment_types_id ON public.equipment_types USING btree (id);
ALTER TABLE "public"."equipment_items" ADD FOREIGN KEY ("type_id") REFERENCES "public"."equipment_types"("id");


-- Indices
CREATE UNIQUE INDEX ix_equipment_items_equipment_id ON public.equipment_items USING btree (equipment_id);
CREATE INDEX ix_equipment_items_id ON public.equipment_items USING btree (id);
ALTER TABLE "public"."events" ADD FOREIGN KEY ("camera_id") REFERENCES "public"."cameras"("id");


-- Indices
CREATE INDEX ix_events_event_type ON public.events USING btree (event_type);
CREATE INDEX ix_events_id ON public.events USING btree (id);
ALTER TABLE "public"."security_alerts" ADD FOREIGN KEY ("camera_id") REFERENCES "public"."cameras"("id") ON DELETE SET NULL;


-- Indices
CREATE INDEX ix_security_alerts_id ON public.security_alerts USING btree (id);


-- Indices
CREATE INDEX ix_security_rules_id ON public.security_rules USING btree (id);
CREATE INDEX ix_security_rules_target_area ON public.security_rules USING btree (target_area);
ALTER TABLE "public"."equipment_tracking" ADD FOREIGN KEY ("camera_id") REFERENCES "public"."cameras"("id");
ALTER TABLE "public"."equipment_tracking" ADD FOREIGN KEY ("equipment_item_id") REFERENCES "public"."equipment_items"("id");


-- Indices
CREATE INDEX ix_equipment_tracking_id ON public.equipment_tracking USING btree (id);


-- Indices
CREATE UNIQUE INDEX ix_users_username ON public.users USING btree (username);
CREATE INDEX ix_users_id ON public.users USING btree (id);


-- Indices
CREATE INDEX ix_cameras_id ON public.cameras USING btree (id);


-- Indices
CREATE INDEX ix_patients_id ON public.patients USING btree (id);
CREATE INDEX ix_patients_name ON public.patients USING btree (name);
CREATE UNIQUE INDEX ix_patients_mrn ON public.patients USING btree (mrn);
ALTER TABLE "public"."consultations" ADD FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id");


-- Indices
CREATE INDEX ix_consultations_id ON public.consultations USING btree (id);
ALTER TABLE "public"."medical_reports" ADD FOREIGN KEY ("patient_id") REFERENCES "public"."patients"("id");


-- Indices
CREATE INDEX ix_medical_reports_id ON public.medical_reports USING btree (id);


-- Indices
CREATE INDEX ix_staff_name ON public.staff USING btree (name);
CREATE INDEX ix_staff_id ON public.staff USING btree (id);
ALTER TABLE "public"."staff_photos" ADD FOREIGN KEY ("staff_id") REFERENCES "public"."staff"("id");


-- Indices
CREATE INDEX ix_staff_photos_id ON public.staff_photos USING btree (id);
ALTER TABLE "public"."attendance" ADD FOREIGN KEY ("staff_id") REFERENCES "public"."staff"("id");
ALTER TABLE "public"."attendance" ADD FOREIGN KEY ("camera_id") REFERENCES "public"."cameras"("id");


-- Indices
CREATE INDEX ix_attendance_staff_name ON public.attendance USING btree (staff_name);
CREATE INDEX ix_attendance_id ON public.attendance USING btree (id);
ALTER TABLE "public"."user_groups" ADD FOREIGN KEY ("user_id") REFERENCES "public"."users"("id");
ALTER TABLE "public"."user_groups" ADD FOREIGN KEY ("group_id") REFERENCES "public"."rbac_groups"("id");


-- Indices
CREATE UNIQUE INDEX ix_rbac_groups_name ON public.rbac_groups USING btree (name);
CREATE INDEX ix_rbac_groups_id ON public.rbac_groups USING btree (id);
ALTER TABLE "public"."group_permissions" ADD FOREIGN KEY ("group_id") REFERENCES "public"."rbac_groups"("id");
ALTER TABLE "public"."group_permissions" ADD FOREIGN KEY ("permission_id") REFERENCES "public"."rbac_permissions"("id");


-- Indices
CREATE UNIQUE INDEX ix_rbac_permissions_name ON public.rbac_permissions USING btree (name);
CREATE INDEX ix_rbac_permissions_id ON public.rbac_permissions USING btree (id);
ALTER TABLE "public"."user_permissions" ADD FOREIGN KEY ("permission_id") REFERENCES "public"."rbac_permissions"("id");
ALTER TABLE "public"."user_permissions" ADD FOREIGN KEY ("user_id") REFERENCES "public"."users"("id");


-- Indices
CREATE INDEX ix_medical_faq_id ON public.medical_faq USING btree (id);
ALTER TABLE "public"."camera_rois" ADD FOREIGN KEY ("camera_id") REFERENCES "public"."cameras"("id");


-- Indices
CREATE INDEX ix_camera_rois_zone_name ON public.camera_rois USING btree (zone_name);
CREATE INDEX ix_camera_rois_id ON public.camera_rois USING btree (id);
ALTER TABLE "public"."conversation_history" ADD FOREIGN KEY ("user_id") REFERENCES "public"."users"("id");


-- Indices
CREATE INDEX ix_conversation_history_id ON public.conversation_history USING btree (id);
CREATE INDEX ix_conversation_history_session_id ON public.conversation_history USING btree (session_id);


-- Indices
CREATE INDEX ix_llm_audit_log_id ON public.llm_audit_log USING btree (id);
CREATE INDEX ix_llm_audit_log_session_id ON public.llm_audit_log USING btree (session_id);


-- Indices
CREATE INDEX ix_knowledge_documents_id ON public.knowledge_documents USING btree (id);
ALTER TABLE "public"."document_chunks" ADD FOREIGN KEY ("document_id") REFERENCES "public"."knowledge_documents"("id");


-- Indices
CREATE INDEX ix_document_chunks_id ON public.document_chunks USING btree (id);
