---
last_mapped_commit: 27e6902b53907ed07de4b811cef911282bfb9800
last_mapped_at: 2026-09-14
---
<!-- refreshed: 2026-09-14 -->

# Architecture

**Analysis Date:** 2026-09-14

## System Overview

```text
┌───────────────────────────────────────────────────────────────────────────┐
│                     Flutter Client (Web / Mobile / Desktop)               │
│  `flutter_source/lib/` — go_router + Provider, feature-folder screens     │
│  (admin/ camera/ indoor_tracking/ security/ agent/ patient_portal/ ...)   │
└───────────────┬───────────────────────────────┬───────────────────────────┘
                │ REST (JWT bearer)              │ WebSocket (frames, events,
                │ `network/api_routes.dart`       │ tracking, calls)
                ▼                                 ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                      FastAPI App — `backend/main.py`                      │
│  Middleware: CORS, AuthenticatedStaticFilesMiddleware (/uploads gate)     │
│  Routers mounted per-domain, some with `dependencies=[auth_dep]`,         │
│  some (websocket-bearing) with per-route auth: `backend/routers/*.py`     │
└───┬───────────┬───────────────┬────────────────┬─────────────┬───────────┘
    │           │               │                │             │
    ▼           ▼               ▼                ▼             ▼
┌────────┐ ┌──────────┐ ┌───────────────┐ ┌──────────────┐ ┌───────────┐
│ Auth / │ │  Camera  │ │    Indoor     │ │  AI Gateway  │ │  Domain   │
│ RBAC   │ │  CV Pipe │ │   Tracking    │ │  (agent chat)│ │ services  │
│`routers│ │`camera/` │ │`indoor_       │ │`services/    │ │(patients, │
│/auth.py│ │(worker + │ │tracking/`     │ │gateway,llm,  │ │ staff,    │
│rbac.py)│ │ subproc  │ │(fusion,gating,│ │routing,tools,│ │ equipment,│
│        │ │ pool)    │ │ hub, floor    │ │memory,       │ │ analytics)│
│        │ │          │ │ cache)        │ │retrieval)    │ │           │
└────┬───┘ └────┬─────┘ └───────┬───────┘ └──────┬───────┘ └─────┬─────┘
     │          │               │                │                │
     └──────────┴───────┬───────┴────────────────┴────────────────┘
                         ▼
        ┌────────────────────────────────────────────────────┐
        │   SQLAlchemy models — `backend/models.py`           │
        │   PostgreSQL + pgvector — `backend/database.py`      │
        │   Alembic migrations — `backend/alembic/versions/`   │
        └────────────────────────────────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| FastAPI app / router wiring | App bootstrap, middleware order, router mounting, auth gating strategy per router | `backend/main.py` |
| Auth & RBAC | Login, JWT issuance/validation, permission checks (`has_permission`, `require_permission`) | `backend/routers/auth.py`, `backend/routers/rbac.py` |
| Camera CV pipeline | RTSP capture loop, face/PPE/pose inference dispatch, WebSocket/WebRTC frame delivery | `backend/camera/worker.py`, `backend/camera/routes.py`, `backend/camera/webrtc.py` |
| Vision inference workers | Isolated subprocess(es) running heavy models (face embeddings, YOLO pose/PPE), shared-memory frame I/O | `backend/camera/vision_worker.py`, `backend/camera/vision_service.py`, `backend/camera/vision_service_zones.py`, `backend/camera/model_manager.py` |
| Attendance | Face-recognition match → attendance session create/checkout, indoor-tracking session start/stop hookup | `backend/camera/attendance_service.py`, `backend/routers/attendance.py` |
| Compliance / security rules | PPE compliance detection, zone/tamper/security rule evaluation from CV + system events | `backend/camera/compliance_engine.py`, `backend/camera/security_rules_service.py`, `backend/rules.py` |
| Equipment tracking | Equipment recognition + location logging from camera frames | `backend/camera/equipment_service.py`, `backend/routers/equipment.py` |
| Indoor location tracking | Camera/WiFi/GPS sensor fusion, geofence gating, live in-memory tracking hub + WebSocket broadcast, floor/room/AP admin config | `backend/indoor_tracking/fusion.py`, `backend/indoor_tracking/gating.py`, `backend/indoor_tracking/hub.py`, `backend/indoor_tracking/floor_cache.py`, `backend/routers/indoor_tracking.py` |
| System events / audit trail | Central event log (SystemEvent), WebSocket broadcast, security-rule trigger hook | `backend/events.py`, `backend/routers/events.py` |
| Correlation engine | Reconstructs daily staff movement timeline from SystemEvents | `backend/correlation_engine.py` |
| AI agent gateway | Orchestrates the "ask the hospital data a question" chat pipeline: cache → intent routing → entity extraction → query planning → tool/vector retrieval → memory → LLM → chart | `backend/services/gateway/ai_gateway.py`, `backend/services/gateway/workflow_engine.py`, `backend/services/gateway/query_planner.py` |
| Intent/model routing | Maps free-text intent to retrieval strategy and to a specific LLM (general vs. clinical/MedGemma vs. vision) | `backend/services/routing/intent_router.py`, `backend/services/routing/llm_router.py` |
| Tool execution (RBAC-gated SQL) | Runs whitelisted parameterized SQL templates per role; denies tools not in a role's `allowed_roles` | `backend/services/tools/tool_registry.py`, `backend/services/tools/tool_executor.py`, `backend/services/retrieval/sql_retriever.py` |
| Vector retrieval / memory | Embedding-based fact/document search, short-term conversation history, long-term memory extraction (encrypted) | `backend/services/retrieval/vector_retriever.py`, `backend/services/memory/memory_manager.py`, `backend/services/memory/memory_extractor.py`, `backend/services/security/encryption.py` |
| Response shaping | Builds LLM prompt context, formats responses, derives chart specs directly from real SQL rows (never LLM text) | `backend/services/llm/context_builder.py`, `backend/services/llm/response_formatter.py`, `backend/services/llm/chart_builder.py` |
| LLM access layer | Chooses/loads local or API-backed model (general vs. MedGemma clinical vs. vision), generates completions | `backend/services/llm_manager.py` |
| Patient/consultation domain | Patient records, consultation transcription (faster-whisper) + discharge-summary generation (Gemini/MedGemma), patient portal | `backend/main.py` (consultation endpoints), `backend/routers/patients.py`, `backend/routers/patient_portal.py` |
| Voice/video calls | WebRTC signaling for doctor↔patient calls | `backend/routers/calls.py`, `backend/services/calls/authorization.py` |
| RFID | Physical badge enroll/verify (device-bearer auth) and admin device management (JWT auth) mixed in one router; token is an encrypted opaque value, never stored in the clear | `backend/routers/rfid.py` |
| Site/tenant config | Hospital branding, first-run setup wizard | `backend/routers/site_config.py`, `backend/routers/setup.py` |
| Data layer | ORM models, DB session/engine, schema migrations | `backend/models.py`, `backend/database.py`, `backend/alembic/` |

## Pattern Overview

**Overall:** Modular monolith — a single FastAPI process exposing many domain routers, backed by one PostgreSQL (+ pgvector) database, with two forms of concurrency carved out for CPU-bound work: OS threads (per-camera capture loop, background embedding load, memory extraction) and separate **processes** for GPU/CPU-heavy inference (vision, audio/whisper), communicating via multiprocessing queues and shared memory.

**Key Characteristics:**

- Router-per-domain FastAPI app; routers vary in auth strategy (blanket `dependencies=[Depends(get_current_user)]` vs. per-route checks for anything carrying a `@router.websocket` route, since FastAPI router-level `dependencies=` doesn't reach websocket handlers).
- RBAC is data-driven: `RBACPermission`/`RBACGroup` rows plus a `role` string column on `User`; `has_permission()`/`require_permission()` in `backend/routers/auth.py` are the single enforcement point reused everywhere (routers, AI tool executor, RFID admin routes).
- The "AI agent" subsystem (`backend/services/`) is architected as its own internal pipeline (gateway → workflow engine → routing/entities/planning → retrieval → LLM → formatting), separate from the CRUD-style domain routers.
- Heavy CV/audio inference is deliberately isolated in subprocesses (`vision_worker.py`, `audio_worker.py`) so model loading happens once per process and a crash/slowdown in inference can't block the FastAPI event loop or the capture thread.
- Indoor tracking state is intentionally NOT persisted per-fix (in-memory `IndoorTrackingHub` only) — a documented product trade-off, not an oversight.
- Frontend mirrors backend domain boundaries almost 1:1 (feature folder per router group: `camera/`, `indoor_tracking/`, `security/`, `agent/`, `patient_portal/`, `settings/`).

## Layers

**API/Router Layer:**

- Purpose: HTTP/WebSocket entry points, request validation (Pydantic), auth dependency wiring
- Location: `backend/routers/*.py`, `backend/camera/routes.py`
- Contains: FastAPI `APIRouter`s, Pydantic request/response schemas
- Depends on: Service layer, `database.get_db`, `routers/auth.py` for auth deps
- Used by: `backend/main.py` (mounts every router)

**Service / Domain Logic Layer:**

- Purpose: Business logic that isn't pure request/response plumbing — attendance matching, compliance evaluation, AI pipeline orchestration
- Location: `backend/camera/*_service.py`, `backend/services/**`, `backend/indoor_tracking/*.py`, `backend/rules.py`, `backend/correlation_engine.py`, `backend/events.py`
- Contains: Stateful singletons (`event_engine`, `hub`, `tool_executor`, `workflow_engine`, `ai_gateway`), pure functions (`indoor_tracking/fusion.py` is explicitly DB-free/pure for testability)
- Depends on: Data layer (`models.py`, `database.SessionLocal`), each other (e.g. `workflow_engine` depends on nearly every `services/*` submodule)
- Used by: Router layer

**Inference / Worker Layer:**

- Purpose: Isolate GPU/CPU-heavy ML inference from the request/response path
- Location: `backend/camera/vision_worker.py`, `backend/camera/audio_worker.py`, `backend/camera/model_manager.py`, `backend/camera/vision_service*.py`
- Contains: `multiprocessing` worker processes, `shared_memory` frame buffers, model loading (YOLO pose/PPE, face embeddings, OpenVINO models under `backend/models/`)
- Depends on: Nothing above it (feeds results back via queues to `camera/worker.py`)
- Used by: `backend/camera/worker.py` (per-camera capture thread)

**Data Layer:**

- Purpose: Persistence and schema
- Location: `backend/models.py` (all SQLAlchemy models in one module), `backend/database.py` (engine/session), `backend/alembic/versions/`
- Contains: ORM model classes, `Base.metadata.create_all()` bootstrap (see TODO in `main.py` about migrating fully to Alembic), migration scripts
- Depends on: PostgreSQL + `pgvector` extension (created at startup in `main.py`)
- Used by: Every service/router that needs persistence

**Frontend Layer (Flutter):**

- Purpose: Cross-target (web/mobile/desktop) UI, session/state management, realtime consumption of backend WebSockets
- Location: `flutter_source/lib/`
- Contains: Feature-folder screens, `providers/` (ChangeNotifier state), `network/` (HTTP client + route constants + environment switch)
- Depends on: Backend REST/WebSocket API only (no direct DB access)
- Used by: End users (web/mobile/desktop builds)

## Data Flow

### Camera → Attendance / Compliance / Events Path

1. `CameraWorker._run` (`backend/camera/worker.py`) pulls RTSP frames on a dedicated thread per camera.
2. Frame handed to `vision_process_manager` → shared-memory IPC → `_vision_worker_process` (`backend/camera/vision_worker.py`) → `VisionServiceZones` (`backend/camera/vision_service_zones.py`) runs face-recognition + pose/PPE inference.
3. Result routed back into `worker.py`, which calls `_maybe_mark_attendance` (`backend/camera/attendance_service.py`) — creates/updates an `Attendance` row and starts an indoor-tracking session via `indoor_tracking/hub.py`.
4. `compliance_engine` (`backend/camera/compliance_engine.py`) and `security_rules_service`/`rules.py` evaluate PPE/zone/tamper conditions and call `event_engine.publish_event()` (`backend/events.py`).
5. `event_engine` writes a `SystemEvent` row, evaluates `security_rules_engine` (`backend/rules.py`) for alert generation, then broadcasts over the `/api/events/ws` WebSocket to connected clients.
6. Frontend `camera/camera_stream_view.dart` / `security/security_dashboard.dart` consume the live WebSocket feed and REST endpoints (`backend/routers/camera_api.py`, `backend/routers/security.py`).

### Indoor Tracking Path

1. Client (mobile app, background service) POSTs WiFi/GPS signal readings to `backend/routers/indoor_tracking.py` (`SignalRequest`), or a camera-seen event arrives via the camera path above.
2. `indoor_tracking/fusion.py` combines available signals (camera > wifi > gps priority) into a single `FusedPosition` (pure, DB-free functions).
3. `indoor_tracking/gating.py` applies geofence/pause logic (e.g. `paused_outside_geofence`).
4. `indoor_tracking/hub.py` (`IndoorTrackingHub`) updates in-memory `TrackingState` per active attendance session and broadcasts to Super Admin WebSocket watchers scoped by `floor_id` — no per-fix history is persisted (see module docstring).
5. Frontend `indoor_tracking/indoor_tracking_ws_client.dart` renders the live map; `tracking_signal_service.dart` is the client-side signal producer.

### AI Agent Chat Path

1. Frontend `agent/agent_screen.dart` posts a message to the agent router (`backend/routers/agent.py`) → `ai_gateway.handle_request()`.
2. `AIGateway` checks a role-scoped cache (`services/retrieval/cache_manager.py`) — cache key includes `role` specifically to prevent a cached answer for one role leaking to a role that would otherwise be denied.
3. On a miss, `WorkflowEngine.execute_workflow()` (`backend/services/gateway/workflow_engine.py`) runs: intent detection → model selection → entity extraction → query planning (SQL tool vs. vector search) → `tool_executor.execute_tool()` (RBAC-checked against `agent_config.json`'s `allowed_roles`, raises `ToolAccessDenied`) → memory/history retrieval (with an L2-distance relevance threshold) → LLM generation (`llm_manager`) → chart spec built directly from SQL rows (never from LLM text, to avoid hallucinated numbers) → async background long-term memory extraction.
4. Response returned as `{"text": ..., "chart": ...}`.

**State Management:**

- Backend: mostly stateless request handlers backed by PostgreSQL; a small number of intentional in-process singletons hold live state that is not persisted (`event_engine.active_websockets`, `hub._sessions`/`_watchers`, `global_zone_alerts`, login-attempt tracker in `auth.py`) — all explicitly documented as per-process/in-memory and not safe across multiple `uvicorn --workers N` processes without a shared store (Redis is proposed elsewhere for that).
- Frontend: `provider`/`ChangeNotifier` (`AuthProvider`, `SiteConfigProvider`, `ThemeProvider`, `AgentProvider`, `CallService`) instantiated once in `main.dart` and provided app-wide via `MultiProvider`; screen-local state is plain `StatefulWidget`.

## Key Abstractions

**RBAC Permission Check:**

- Purpose: Single source of truth for "can this user do X"
- Examples: `has_permission()` / `require_permission()` in `backend/routers/auth.py`; reused by `backend/services/tools/tool_executor.py` (AI tool access) and by the Flutter `AuthProvider.hasPermission()` / `app_router.dart`'s `permissionForPath()`
- Pattern: `superadmin` role always bypasses; otherwise checks `User.direct_permissions` then each `User.groups[].permissions`

**Worker Manager (subprocess pool):**

- Purpose: Load heavy models once per process, dispatch frames across N worker processes for parallelism
- Examples: `vision_process_manager` (`backend/camera/vision_worker.py`), `audio_process_manager` (`backend/camera/audio_worker.py`)
- Pattern: `multiprocessing.Queue` request/response protocol + `shared_memory.SharedMemory` for zero-copy frame transfer, keyed by `camera_id`

**Event Engine (pub/sub over WebSocket):**

- Purpose: Persist + fan out real-time system events to connected clients
- Examples: `event_engine` (`backend/events.py`), `hub` (`backend/indoor_tracking/hub.py`) — same connect/disconnect/broadcast shape
- Pattern: `Set`/`Dict` of live `WebSocket` objects guarded by a lock; `asyncio.run_coroutine_threadsafe` used to push from non-event-loop threads

**Sensor Fusion Candidate/FusedPosition:**

- Purpose: Represent and combine competing location signals with confidence/accuracy
- Examples: `Candidate`, `FusedPosition` dataclasses in `backend/indoor_tracking/fusion.py`
- Pattern: Pure functions returning `Optional[Candidate]`, combined by a fusion function — no DB access, directly unit-testable (see `backend/test_indoor_tracking.py`)

**AI Tool Registry:**

- Purpose: Declarative, RBAC-scoped SQL query templates the agent can invoke
- Examples: `backend/services/tools/tool_registry.py`, config in `backend/agent_config.json`
- Pattern: Tool config declares `required_parameters`, `sql_template`, `allowed_roles`; `tool_executor.py` validates params and role before running `sql_retriever.execute()`

**NavEntry (Flutter nav/permission map):**

- Purpose: One source of truth for a top-level route's path, required permission, icon/label, and screen builder
- Examples: `kNavEntries` in `flutter_source/lib/app_router.dart`
- Pattern: Both the `GoRouter` route table and `SharedAppDrawer`/mobile bottom nav read this same list, so adding a section requires one edit, not several

## Entry Points

**Backend HTTP/WebSocket server:**

- Location: `backend/main.py` (`app = FastAPI(...)`), started via `backend/start.sh` / `uvicorn`
- Triggers: `lifespan()` context manager on startup — cleans up orphaned subprocesses, provisions the fixed RFID station, loads staff face embeddings in a background thread
- Responsibilities: Middleware registration (CORS, `AuthenticatedStaticFilesMiddleware` for `/uploads`), mounting every domain router, a handful of inline consultation endpoints (transcribe, generate/list/delete consultations)

**Flutter app:**

- Location: `flutter_source/lib/main.dart` (`main()`)
- Triggers: App launch on web/mobile/desktop
- Responsibilities: Initializes `EnvironmentConfig` (dev/staging/prod base URL), Mapbox token, restores JWT session (`AuthProvider.tryAutoLogin()`), fetches site branding, builds the `GoRouter` (`flutter_source/lib/app_router.dart`) and wraps the app in `MultiProvider`

**Camera capture entry:**

- Location: `backend/camera/routes.py` (start/stop endpoints), `backend/camera/worker.py` (`CameraWorker.start()`)
- Triggers: Admin action (add/enable a camera) or app startup reconnect logic
- Responsibilities: Spins up a per-camera capture thread and registers it with the shared vision/audio worker pools

**Docker deployment:**

- Location: `Dockerfile` (CUDA base image, Flutter + Python toolchain), `docker-compose.yml` (`medical-db` pgvector Postgres + `medial-agent` app container), `start_services.sh`
- Responsibilities: Single-host GPU deployment; `shm_size: "8g"` and `ipc: host` in compose are required for the vision worker's shared-memory frame IPC

## Architectural Constraints

- **Threading/process model:** Per-camera capture runs on a Python thread; heavy inference runs in separate `multiprocessing` worker processes (`vision_worker.py`, `audio_worker.py`) communicating via queues + `shared_memory`. FastAPI's own request handling is asyncio-based (single process by default — see login-rate-limit comment in `auth.py` about `uvicorn --workers N` not being safely supported yet without a shared store).
- **Global/module-level state:** `event_engine` (`backend/events.py`), `hub` (`backend/indoor_tracking/hub.py`), `global_zone_alerts` (`backend/events.py`), `_login_failures` (`backend/routers/auth.py`), `ai_gateway`/`workflow_engine`/`tool_executor`/`memory_manager` (`backend/services/**`) are all process-wide singletons instantiated at import time. None of this is safe for multi-process/multi-worker deployment without adding a shared backing store (Redis proposed in `docs/scaling-architecture.md`).
- **DB bootstrap in transition:** `models.Base.metadata.create_all(bind=engine)` still runs on every startup in `main.py` alongside a real Alembic setup (`backend/alembic/`) — see the `TODO(migrations)` comment there; `alter_db.py`/`migrate_db.py`/`backfill_db.py` at repo root are legacy hand-run patch scripts predating Alembic.
- **Indoor tracking is not persisted per-fix:** `IndoorTrackingHub` is explicitly in-memory-only by product decision (see `backend/indoor_tracking/hub.py` module docstring) — a process restart loses all live position state.
- **Websocket routers can't use FastAPI's router-level `dependencies=`:** any router with a `@router.websocket` route (`security`, `events`, `indoor_tracking`, `rfid`, `calls`) is mounted in `main.py` *without* `dependencies=[auth_dep]` and instead checks auth per-HTTP-route internally — a pattern that must be followed by any new router adding a websocket.

## Anti-Patterns

### Multiple hand-rolled schema-patch scripts alongside Alembic

**What happens:** `backend/alter_db.py`, `backend/migrate_db.py`, `backend/backfill_db.py` exist as one-off scripts to patch the live DB, while `backend/alembic/versions/` is the "real" migration history and `main.py` still calls `Base.metadata.create_all()` on every boot.
**Why it's wrong:** Three sources of schema truth (models.py + create_all, the patch scripts, Alembic) make it easy for a deployed DB's actual schema to drift from what any one of them assumes.
**Do this instead:** New schema changes should go through an Alembic revision in `backend/alembic/versions/`; treat the root-level patch scripts as legacy/one-shot and do not add new ones.

### Business logic occasionally inline in `main.py`

**What happens:** The consultation transcribe/generate/list/delete endpoints and their prompt-construction/validation logic (`_generate_discharge_summary`, `_looks_like_preamble`) live directly in `backend/main.py` rather than a `routers/consultations.py` + service module, unlike every other domain (patients, staff, equipment, etc.) which has its own router file.
**Why it's wrong:** Breaks the otherwise consistent "one router file per domain" convention, making `main.py` a mix of app bootstrap and domain logic.
**Do this instead:** New consultation-related endpoints should be extracted into a dedicated `backend/routers/consultations.py` following the pattern of `backend/routers/patients.py`.

## Error Handling

**Strategy:** FastAPI `HTTPException` for expected/validated failures (permission denied, not found, bad input); broad `except Exception` + `traceback.print_exc()` + re-raise as `HTTPException(500, ...)` at the outer boundary of long-running endpoints (audio transcription, consultation generation).

**Patterns:**

- Domain-specific exceptions (e.g. `ToolAccessDenied` in `services/tools/tool_executor.py`) are caught at the workflow layer and converted into a user-facing message rather than a stack trace, deliberately avoiding a silent LLM fallback that might hallucinate.
- Background/best-effort operations (event broadcast, embedding reload, RFID station provisioning at startup) swallow exceptions and log, so a non-critical failure never blocks the request path or app startup.

## Cross-Cutting Concerns

**Logging:** `print()`-based, prefixed by component in brackets (e.g. `[AIGateway]`, `[ToolExecutor]`, `[EventEngine]`, `[VisionWorkerProcess]`) — no structured logging framework in use.

**Validation:** Pydantic models per router for request/response schemas; ad hoc guardrails for LLM output specifically (`MIN_TRANSCRIPT_WORDS`, `_looks_like_preamble` in `main.py`) since generated clinical text is shown directly to patients/staff.

**Authentication:** JWT bearer tokens (`backend/routers/auth.py`, `SECRET_KEY`/`ALGORITHM`), required env-set `SECRET_KEY` (fails startup loudly if unset, opt-in insecure default only via `ALLOW_INSECURE_DEFAULT_SECRET=1`); per-route auth for websocket-bearing routers; a separate device-bearer-key auth path for physical RFID readers (`routers/rfid.py`).

---

*Architecture analysis: 2026-09-14*
