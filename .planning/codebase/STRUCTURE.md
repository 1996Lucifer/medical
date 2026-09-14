---
last_mapped_commit: 27e6902b53907ed07de4b811cef911282bfb9800
last_mapped_at: 2026-09-14
---
# Codebase Structure

**Analysis Date:** 2026-09-14

## Directory Layout

```
medical_agent/
├── backend/                        # FastAPI/Python service (CV, RBAC, AI agent, data)
│   ├── main.py                     # App bootstrap, middleware, router mounting, consultation endpoints
│   ├── models.py                   # ALL SQLAlchemy ORM models (single module)
│   ├── database.py                 # Engine/session factory, DATABASE_URL
│   ├── events.py                   # SystemEvent publish + WebSocket broadcast (EventEngine)
│   ├── rules.py                    # Security rules engine (event → alert evaluation)
│   ├── correlation_engine.py       # Daily staff-movement timeline reconstruction
│   ├── agent_config.json           # AI tool registry config (allowed_roles, sql_template, params)
│   ├── alter_db.py / migrate_db.py / backfill_db.py  # Legacy one-shot DB patch scripts (pre-Alembic)
│   ├── seed_rbac.py / seed_hospital_roles.py         # RBAC/role seed scripts
│   ├── requirements.txt, alembic.ini, start.sh
│   ├── routers/                    # One file per domain — HTTP/WS entry points
│   ├── camera/                     # CV capture, inference workers, attendance/compliance/equipment
│   ├── indoor_tracking/            # Sensor fusion, geofence gating, live tracking hub, floor cache
│   ├── services/                   # AI agent pipeline + cross-cutting service modules
│   ├── config/                     # Runtime-tunable JSON config (ppe_colors.json, vlm_config.json)
│   ├── models/                     # Downloaded/cached ML model weights (openvino, huggingface cache)
│   ├── alembic/                    # Migration environment + versions/
│   └── uploads/                    # Runtime-written files (staff photos, incidents, reports, branding)
├── flutter_source/                 # Flutter app (web/mobile/desktop targets)
│   ├── lib/
│   │   ├── main.dart               # App entry, provider wiring, session restore
│   │   ├── app_router.dart         # go_router routes, NavEntry table, permission-gated redirects
│   │   ├── network/                # HTTP client, API route constants, environment switch
│   │   ├── providers/              # ChangeNotifier app-wide state (auth, site config, theme, agent)
│   │   ├── storage/                # flutter_secure_storage wrapper
│   │   └── <feature>/              # One folder per domain screen group (see below)
│   ├── android/ ios/ linux/ macos/ web/ windows/   # Platform embedding shells (generated + platform code)
│   ├── assets/                     # Bundled images/fonts
│   └── test/                       # Default Flutter widget test scaffold (minimal coverage)
├── docs/                           # Architecture/audit notes (scaling, MVP gaps, UI audit)
├── init_db/                        # Postgres init scripts mounted into the `medical-db` container
├── docker-compose.yml, Dockerfile  # Single-host GPU deployment (CUDA base image, pgvector Postgres)
├── manage.sh, start_services.sh, setup_commands.sh, run_schema.sh   # Ops scripts
├── schema.sql, data.sql, equipment_types.sql                        # Reference SQL dumps/seed data
└── *.md (README, database.md, walkthrough.md, PPE_Compliance_Architecture.md, etc.)  # Root-level docs
```

## Directory Purposes

**`backend/routers/`:**

- Purpose: HTTP/WebSocket endpoints, one file per domain, thin — delegates to `camera/`, `indoor_tracking/`, or `services/` for logic
- Contains: FastAPI `APIRouter` instances, Pydantic schemas colocated with their endpoints
- Key files: `auth.py` (JWT + login rate limiting), `rbac.py` (role/permission admin), `staff.py` (largest router — staff CRUD + embeddings + websocket), `indoor_tracking.py`, `rfid.py` (dual auth model: JWT for admin, device-bearer-key for hardware), `site_config.py`, `setup.py` (first-run wizard)

**`backend/camera/`:**

- Purpose: Everything CV/camera-related — capture, inference dispatch, attendance/compliance/equipment derived from vision
- Contains: `worker.py` (per-camera capture thread + shared client-queue fanout), `vision_worker.py`/`audio_worker.py` (subprocess managers), `vision_service.py`/`vision_service_zones.py` (inference + zone logic), `model_manager.py` (model loading), `attendance_service.py`, `compliance_engine.py`, `equipment_service.py`, `security_rules_service.py`, `routes.py` (camera HTTP/WS routes), `webrtc.py`, `constants/` (tunable thresholds, message strings)
- Key files: `worker.py` (1350 lines — largest file in backend), `vision_service_zones.py` (1272 lines)

**`backend/indoor_tracking/`:**

- Purpose: Indoor positioning domain logic, deliberately separated from `routers/indoor_tracking.py` (the HTTP/WS layer)
- Contains: `fusion.py` (pure sensor-fusion functions, camera/wifi/gps → `FusedPosition`), `gating.py` (geofence pause/resume), `hub.py` (in-memory live session state + WebSocket broadcast), `floor_cache.py` (cached room/floor lookups with invalidation)

**`backend/services/`:**

- Purpose: The AI agent ("ask a question about hospital data") pipeline, organized as its own layered subsystem
- Contains subpackages:
  - `gateway/` — `ai_gateway.py` (caching wrapper), `workflow_engine.py` (pipeline orchestrator), `query_planner.py` (SQL-tool vs. vector strategy)
  - `routing/` — `intent_router.py`, `llm_router.py` (model selection)
  - `entities/` — `entity_extractor.py`
  - `tools/` — `tool_registry.py` (reads `agent_config.json`), `tool_executor.py` (RBAC-gated SQL execution)
  - `retrieval/` — `sql_retriever.py`, `vector_retriever.py`, `cache_manager.py`
  - `memory/` — `memory_manager.py` (short-term history), `memory_extractor.py` (background long-term fact extraction)
  - `llm/` — `context_builder.py`, `response_formatter.py`, `chart_builder.py`
  - `security/` — `encryption.py` (memory-fact encryption at rest)
  - `metrics/` — `metrics.py` (interaction logging)
  - `calls/` — `authorization.py` (call permission checks)
  - `llm_manager.py` — top-level model access (general/clinical/vision), sits directly under `services/`, not a subpackage

**`backend/config/`:**

- Purpose: Operator-tunable runtime config, loaded (not hardcoded) so thresholds can change without a redeploy
- Contains: `ppe_colors.json` (PPE color-detection tolerances), `vlm_config.json` (VLM polling toggle/interval)

**`backend/models/`:**

- Purpose: Local ML model artifacts
- Contains: `best_openvino_model/` (converted inference model), `.cache/huggingface/` (downloaded model cache)
- Generated: Yes (via `download_models.py`) — not hand-authored code

**`backend/alembic/`:**

- Purpose: Schema migration history (the intended long-term source of truth, alongside `models.py`)
- Contains: `env.py`, `versions/*.py` — sequential + a couple of hash-named revisions (`4a29336e9be2_add_rfid_card_support.py` etc., mixed naming from merges)

**`backend/uploads/`:**

- Purpose: Runtime-written file storage, served (auth-gated except `/branding/*`) via `StaticFiles` mount in `main.py`
- Contains: `staff/` (photos), `incidents/` (snapshots), `reports/`, `branding/` (public logo), `floorplans/`
- Generated: Yes, at runtime. Committed: No (should be gitignored)

**`flutter_source/lib/<feature>/`:**

- Purpose: One folder per domain screen group, mirroring backend router boundaries
- Folders: `admin/` (super admin dashboard), `agent/` (AI chat), `analytics/`, `auth/` (login, setup wizard, change password), `call/` (WebRTC call UI + service), `camera/`, `consultation/`, `directory/` (people directory), `indoor_tracking/`, `patient_portal/`, `patients/`, `profile/`, `security/`, `settings/` (staff/camera/RBAC/analytics management sub-screens)
- Convention: Each feature folder holds its own screen(s) plus any feature-local service (e.g. `camera/camera_status_service.dart`, `indoor_tracking/tracking_signal_service.dart`, `indoor_tracking/indoor_tracking_ws_client.dart`)

**`flutter_source/lib/network/`:**

- Purpose: All backend communication concerns, centralized
- Contains: `network_manager.dart` (singleton HTTP client, attaches bearer token), `api_routes.dart` (every backend URL as a static getter/function, grouped by domain with comments), `environment.dart` (dev/staging/prod base URL switch via `--dart-define=ENV=`), `rfid_service.dart`, `admin_dashboard_service.dart`

**`flutter_source/lib/providers/`:**

- Purpose: App-wide `ChangeNotifier` state, instantiated once in `main.dart` and injected via `MultiProvider`
- Contains: `auth_provider.dart` (session, JWT, permissions, patient/staff id), `site_config_provider.dart` (branding), `theme_provider.dart`, `agent_provider.dart`

**`flutter_source/lib/utils/`:**

- Purpose: Small cross-platform shims
- Contains: `network.dart`/`network_io.dart`/`network_web.dart`/`network_stub.dart` — conditional-import pattern for platform-specific networking (native vs. web)

**`docs/`:**

- Purpose: Standing architecture/product docs, not generated
- Contains: `scaling-architecture.md`, `mvp-gap-audit.md`, `ui-design-audit.md`, `designs/compliance-audit-report-wedge.md`

## Key File Locations

**Entry Points:**

- `backend/main.py`: FastAPI app object, middleware, router mounts, startup lifespan
- `flutter_source/lib/main.dart`: Flutter app entry, provider/session bootstrap
- `flutter_source/lib/app_router.dart`: Route table + permission gating (`kNavEntries`, `buildAppRouter`)

**Configuration:**

- `backend/.env` / `.env.example`: `DATABASE_URL`, `SECRET_KEY`, `GEMINI_API_KEY`, etc. (never read/quoted — see forbidden-files policy)
- `backend/agent_config.json`: AI tool registry (per-tool `allowed_roles`, SQL templates, required params)
- `backend/config/ppe_colors.json`, `backend/config/vlm_config.json`: CV runtime tuning
- `flutter_source/lib/network/environment.dart`: Backend base URL per build environment
- `docker-compose.yml` / `Dockerfile`: Deployment topology, GPU/shared-memory requirements

**Core Logic:**

- `backend/models.py`: All ORM models
- `backend/camera/worker.py`: Camera capture orchestration
- `backend/indoor_tracking/fusion.py`: Sensor fusion math
- `backend/services/gateway/workflow_engine.py`: AI agent pipeline orchestration
- `backend/routers/auth.py`: Auth/RBAC primitives (`has_permission`, `require_permission`)

**Testing:**

- `backend/test_indoor_tracking.py`: Unit tests for the pure fusion/gating functions (only backend test file found)
- `flutter_source/test/widget_test.dart`: Default Flutter counter-app widget test (not updated for this app — minimal frontend test coverage)

## Naming Conventions

**Files:**

- Backend: `snake_case.py`; router files named after the domain noun (`staff.py`, `attendance.py`, `equipment.py`); service files often suffixed `_service.py` / `_engine.py` / `_manager.py` / `_extractor.py` indicating their role (e.g. `attendance_service.py`, `security_rules_engine` inside `rules.py`, `cache_manager.py`, `memory_extractor.py`)
- Frontend: `snake_case.dart` per Dart convention; screen files suffixed `_screen.dart`, services suffixed `_service.dart`, providers suffixed `_provider.dart`

**Directories:**

- Backend: lowercase, domain-named (`camera/`, `indoor_tracking/`, `services/`), with `services/` further split into single-purpose subpackages (`gateway/`, `routing/`, `tools/`, `retrieval/`, `memory/`, `llm/`, `security/`, `metrics/`, `calls/`, `entities/`)
- Frontend: lowercase, one folder per feature/domain matching backend router naming where applicable (`camera/`, `indoor_tracking/`, `security/`, `agent/`)

**Classes/Singletons (backend):**

- Stateful singletons are instantiated at module bottom and exported lowercase (e.g. `event_engine = EventEngine()`, `hub = IndoorTrackingHub()`, `ai_gateway = AIGateway()`, `workflow_engine = WorkflowEngine()`, `tool_executor = ToolExecutor()`) — import the lowercase instance, not the class, elsewhere in the codebase.

## Where to Add New Code

**New backend domain/feature (CRUD-style):**

- Router: `backend/routers/<domain>.py` (new file, `APIRouter(prefix="/api/<domain>", tags=["<domain>"])`)
- Models: add to `backend/models.py` (single-file convention — do not create a new models module)
- Migration: new Alembic revision in `backend/alembic/versions/` (do NOT rely on `Base.metadata.create_all()` for anything beyond brand-new tables — see `main.py`'s `TODO(migrations)`)
- Mount: register in `backend/main.py`, choosing blanket `dependencies=auth_dep` unless the router has a `@router.websocket` route (then per-route auth, following `indoor_tracking.py`'s pattern)

**New AI agent tool:**

- Add an entry to `backend/agent_config.json` (SQL template, required params, `allowed_roles`)
- No code change needed unless the query strategy itself is new — `tool_executor.py` and `tool_registry.py` are generic over config

**New CV capability (e.g. a new detection type):**

- Inference logic: `backend/camera/vision_service_zones.py` or a new `backend/camera/<capability>_service.py` following `equipment_service.py`/`attendance_service.py`'s `_maybe_track_x(...)` pattern
- Wire into the per-frame loop in `backend/camera/worker.py`

**New Flutter screen/feature:**

- Screen: new folder under `flutter_source/lib/<feature>/`, `<feature>_screen.dart`
- Route + nav entry: add to `kNavEntries` in `flutter_source/lib/app_router.dart` (only if it's a top-level nav destination) or as a standalone `GoRoute` with `parentNavigatorKey: rootNavigatorKey` (if it's a drill-down page like `/patients/:id` or a `/settings/*` sub-page)
- API endpoints: add getters/functions to `flutter_source/lib/network/api_routes.dart`, grouped under a comment for the relevant domain

**Utilities:**

- Backend shared helpers: `backend/camera/utils.py` (camera-specific), or a new top-level module if truly cross-domain (mirrors existing `events.py`, `rules.py`, `correlation_engine.py` placement at `backend/` root for cross-cutting concerns)
- Frontend shared helpers: `flutter_source/lib/utils/`; shared widgets in `flutter_source/lib/widgets/`

## Special Directories

**`backend/uploads/`:**

- Purpose: Runtime file storage (staff photos, incident snapshots, reports, floorplans, branding)
- Generated: Yes
- Committed: No (runtime data — ensure `.gitignore` covers it)

**`backend/models/`:**

- Purpose: Downloaded/converted ML model weights and Hugging Face cache
- Generated: Yes (via `backend/download_models.py`)
- Committed: No

**`flutter_source/build/`, `flutter_source/.dart_tool/`:**

- Purpose: Flutter build artifacts and tool cache
- Generated: Yes
- Committed: No

**`backend/alembic/versions/`:**

- Purpose: Ordered schema migration scripts
- Generated: Partially (scaffolded by `alembic revision`, hand-edited for actual DDL)
- Committed: Yes

---

*Structure analysis: 2026-09-14*
