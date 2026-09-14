---
last_mapped_commit: 27e6902b53907ed07de4b811cef911282bfb9800
last_mapped_at: 2026-09-14
---
# External Integrations

**Analysis Date:** 2026-09-14

## APIs & External Services

**AI / LLM:**

- Google Gemini (`google-genai` SDK) - Cloud LLM client
  - SDK/Client: `google.genai.Client`, instantiated in `backend/main.py` (`client = genai.Client(api_key=GENAI_API_KEY)`)
  - Auth: `GEMINI_API_KEY` env var (from Google AI Studio, per `backend/.env.example`)
  - Note: client object is constructed at module load but no endpoint in the reviewed routers currently calls `client.*` — appears to be either legacy/in-progress wiring or reserved for a not-yet-active code path. The active chat/summarization pipeline (`backend/main.py::_generate_discharge_summary`, `backend/services/gateway/ai_gateway.py`, `backend/services/routing/llm_router.py`) routes through the local `llm_manager` (MedGemma/Qwen3 GGUF models) instead.
- Local LLM inference (no external network call) - `llama-cpp-python` running `backend/models/MedGemma.gguf` (clinical, with `mmproj-F16.gguf` vision projector) and `backend/models/Qwen3.gguf`/`Qwen31.gguf` (general hospital ops/security), orchestrated by `backend/services/llm_manager.py`

**Home Assistant (documented, not implemented):**

- `HOME_ASSISTANT_URL` / `HOME_ASSISTANT_TOKEN` are defined in `backend/.env.example` as an "Optional" integration, but no code under `backend/` references either variable or makes any Home Assistant API call. Treat as a reserved/planned integration, not a live one.

**Mapping:**

- Mapbox (`mapbox_maps_flutter` ^3.0.0-alpha.30, `turf` ^0.0.12) - Interactive indoor/geofence maps
  - Client: `flutter_source/lib/main.dart` (reads `MAPBOX_KEY` via `String.fromEnvironment`, passed at build time with `--dart-define=MAPBOX_KEY=pk.xxxxx`), consumed in `flutter_source/lib/indoor_tracking/hospital_geofence_screen.dart` for drawing geofence polygons on a live Mapbox GL map (web build note: uses `mapbox_maps_flutter_web`/Mapbox GL JS)
  - Auth: Mapbox public access token, injected only at Flutter build time (not stored server-side)

## Data Storage

**Databases:**

- PostgreSQL 16 with `pgvector` extension
  - Connection: `DATABASE_URL` env var (`backend/database.py`, `backend/.env.example`); default fallback `postgresql://postgres:postgres@localhost:5433/medical_agent`
  - Client/ORM: SQLAlchemy (`backend/database.py`), Alembic for migrations (`backend/alembic/`)
  - Vector extension bootstrapped at app startup: `CREATE EXTENSION IF NOT EXISTS vector` (`backend/main.py`)
  - Dockerized instance: `pgvector/pgvector:pg16` image in `docker-compose.yml`, host port `5433`, seed scripts in `init_db/`
  - Used both for relational hospital data (staff, patients, attendance, equipment, cameras, RBAC) and vector embeddings (face-recognition embeddings via InsightFace/ArcFace, semantic memory via `sentence-transformers`, see `backend/services/memory/` and `backend/services/retrieval/vector_retriever.py`)

**File Storage:**

- Local filesystem only - `backend/uploads/` (staff photos, incident snapshots, patient report PDFs under `uploads/reports/`, hospital branding logo under `uploads/branding/`), served via FastAPI `StaticFiles` mount at `/uploads` in `backend/main.py`
- No cloud object storage (S3/GCS/Azure Blob) integration found

**Caching:**

- In-process cache only - `backend/services/retrieval/cache_manager.py` (`cache_manager`), used by `backend/services/gateway/ai_gateway.py` to cache AI chat responses keyed by `role:message`. No Redis/Memcached found.

## Authentication & Identity

**Auth Provider:**

- Custom - No third-party auth provider (no Auth0/Clerk/Firebase Auth/Cognito)
  - Implementation: username/password with `bcrypt` hashing (`backend/routers/auth.py`), JWT session tokens (`pyjwt`, `HS256`, signed with `SECRET_KEY` env var) via `OAuth2PasswordBearer(tokenUrl="/api/auth/login")`
  - App refuses a safe startup if `SECRET_KEY` is unset in production intent, but currently falls back to a hardcoded insecure default (`"super_secret_hospital_key_please_change"`) with a warning log rather than a hard crash — see comments in `backend/routers/auth.py`
  - RBAC (role-based access control): custom graph of users/groups/permissions (`RBACGroup`, `RBACPermission` in `backend/models.py`; management endpoints in `backend/routers/rbac.py`, gated by `require_permission("manage_rbac")`)
  - Static file access (`/uploads`) is separately gated by `AuthenticatedStaticFilesMiddleware` in `backend/main.py`, re-validating the same JWT at the ASGI layer (StaticFiles doesn't support FastAPI `dependencies=`)

**Device Authentication (RFID hardware):**

- A third, distinct auth kind for physical ESP32 + RC522 RFID devices, separate from user JWTs: static `Authorization: Bearer <device_key>` header validated via `get_current_device` in `backend/routers/rfid.py`
- Device keys and card tokens are never stored in plaintext — only their SHA-256 hash (`_hash_token`) is persisted (`models.RfidDevice`, `models.RfidCard`)
- Card tokens themselves are AES-256-GCM encrypted opaque 128-bit values generated by a writer device and never decrypted server-side
- The one fixed admin-desk enrollment station is auto-provisioned at backend startup from `RFID_STATION_DEVICE_KEY` (`backend/routers/rfid.py::ensure_fixed_station`, called from `backend/main.py` lifespan) rather than generated dynamically

## Monitoring & Observability

**Error Tracking:**

- None found (no Sentry/Rollbar/Bugsnag) - errors are logged via `print()`/`traceback.print_exc()` (e.g. `backend/main.py`) and Python's `logging` module (`backend/routers/calls.py`)

**Logs:**

- Plain stdout/file logging - `backend/backend_nohup.log` (nohup output from manual runs), `print()`-based diagnostic logging throughout `backend/camera/`, `backend/services/`, and `backend/main.py`
- `backend/services/metrics/metrics.py` (`metrics_tracker`) - In-house interaction/latency metrics logging for AI gateway requests (intent, strategy, tool, model, latency), not an external APM

## CI/CD & Deployment

**Hosting:**

- Self-hosted / on-premise - Single Docker Compose stack (`docker-compose.yml`) run with `network_mode: host` and NVIDIA GPU passthrough, consistent with an on-site hospital appliance rather than a cloud host
- No cloud provider config (no AWS/GCP/Azure deployment manifests, Terraform, or k8s manifests found)

**CI Pipeline:**

- None found - no `.github/workflows/`, `.gitlab-ci.yml`, or other CI config in the repo

## Environment Configuration

**Required env vars (backend, see `backend/.env.example`):**

- `DATABASE_URL` - PostgreSQL connection string
- `SECRET_KEY` - JWT signing secret (app warns and uses an insecure default if unset)
- `GEMINI_API_KEY` - Google Gemini API key (optional; only needed if Gemini client path is used)
- `HOME_ASSISTANT_URL` / `HOME_ASSISTANT_TOKEN` - Documented as optional; currently unused in code
- `RFID_STATION_DEVICE_KEY` - Pre-shared key for the physical RFID enrollment station

**Build-time config (frontend):**

- `MAPBOX_KEY` - Injected via `--dart-define` at Flutter build time (`flutter_source/lib/main.dart`)
- `flutter_source/lib/network/environment.dart` - Hardcoded `Local` (LAN IP + port 8000), `Staging` (`staging-api.example.com`), and `Production` (`api.example.com`) base URLs/WS URLs selected by build environment

**Secrets location:**

- `backend/.env` (git-ignored, present on disk; contents not read per this audit's forbidden-files policy) is the actual runtime secrets file; `backend/.env.example` documents the expected keys only

## Webhooks & Callbacks

**Incoming (device-initiated, not user-facing HTTP webhooks but functionally equivalent):**

- `POST /api/rfid/checkin` (`backend/routers/rfid.py`) - The physical RFID station self-reports its LAN IP right after connecting to WiFi, so the backend always has a current address for it without any manual configuration (device-key authenticated, not user JWT)
- `POST /api/rfid/enroll` and `POST /api/rfid/verify` (`backend/routers/rfid.py`) - Called directly by unauthenticated-as-a-user physical devices (reader/writer hardware) using the device bearer key, to map/verify RFID card tokens against staff records
- `POST /api/webrtc/offer` (`backend/camera/routes.py`) - WebRTC SDP offer/answer exchange for live camera AI streaming (`mode=webrtc_ai`) or camera management view (`mode=webrtc_manage`); not a third-party webhook but the same signaling-callback shape

**Outgoing:**

- None found - no outbound webhook dispatch to third-party URLs

---

*Integration audit: 2026-09-14*
