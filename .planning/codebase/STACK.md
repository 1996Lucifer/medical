---
last_mapped_commit: 27e6902b53907ed07de4b811cef911282bfb9800
last_mapped_at: 2026-09-14
---
# Technology Stack

**Analysis Date:** 2026-09-14

## Languages

**Primary:**

- Python 3.14 - Backend (`backend/`), FastAPI app, computer-vision workers, AI orchestration
- Dart 3.3+ - Flutter frontend (`flutter_source/`)

**Secondary:**

- SQL - Raw schema/seed scripts (`backend/schema.sql`, `backend/data.sql`, `equipment_types.sql`, Alembic migrations in `backend/alembic/versions/`)
- Shell - Ops scripts (`manage.sh`, `start_services.sh`, `run_schema.sh`, `setup_commands.sh`)

## Runtime

**Environment:**

- Python 3.14 (`backend/.venv` is a Python 3.14 virtualenv; a second env `backend/.venv-glb` also exists — likely for a GPU/library-specific dependency set)
- Flutter SDK (stable channel, installed via `git clone` in `Dockerfile`; app declares `sdk: '>=3.3.0 <4.0.0'` in `flutter_source/pubspec.yaml`)
- NVIDIA CUDA 12.6.3 base image (`Dockerfile` — `nvidia/cuda:12.6.3-devel-ubuntu22.04`), CUDA 12.4 PyTorch wheels installed explicitly
- Designed to also run on Apple Silicon (Mac) via hardware auto-detection in `backend/services/llm_manager.py` (`mlx-lm` engine selection) and `backend/camera/model_manager.py` (CoreML ONNX execution provider)

**Package Manager:**

- pip - Python dependencies (`backend/requirements.txt`); no lockfile (no `requirements-lock.txt`/`poetry.lock`/`Pipfile.lock` present — versions are loosely pinned, most unpinned)
- pub - Dart/Flutter dependencies (`flutter_source/pubspec.yaml`); lockfile present at `flutter_source/pubspec.lock`

## Frameworks

**Core (Backend):**

- FastAPI - HTTP API framework, app defined in `backend/main.py` (`FastAPI(title="Healthcare Operations Copilot API", lifespan=lifespan)`)
- Uvicorn - ASGI server (implied by `uvicorn` dependency; run via `backend/start.sh`)
- SQLAlchemy (`declarative_base`, `sessionmaker`) - ORM, engine configured in `backend/database.py`
- Alembic - Schema migrations (`backend/alembic/`, `backend/alembic.ini`); `backend/main.py` still calls `models.Base.metadata.create_all(bind=engine)` at startup, with a `TODO(migrations)` comment noting the app should switch fully to `alembic upgrade head` once the live DB is bootstrapped onto Alembic
- Pydantic - Request/response models throughout `backend/routers/*.py` and `backend/main.py`
- Starlette - Custom ASGI middleware, e.g. `AuthenticatedStaticFilesMiddleware` in `backend/main.py` gating `/uploads`

**Core (Frontend):**

- Flutter/Dart - Mobile+web+desktop client in `flutter_source/lib/` (screens: `patients/`, `patient_portal/`, `security/`, `auth/`, `camera/`, `admin/`, `indoor_tracking/`, `directory/`, `call/`, `analytics/`, `settings/`)
- `provider` (^6.1.2) - State management
- `go_router` (^17.5.0) - Navigation/routing

**Computer Vision / ML (Backend):**

- InsightFace (`insightface`) - Face detection (SCRFD) + recognition (ArcFace, `buffalo_l` model pack), loaded lazily in `backend/camera/model_manager.py::get_face_analysis` with `allowed_modules=["detection", "recognition"]` only
- Ultralytics YOLO (`ultralytics>=8.3.0`) - Multi-person detection + ByteTrack tracking (`YOLO11n`, `backend/camera/model_manager.py::get_yolo_detector`), plus a separate PPE-compliance YOLO model (ONNX/OpenVINO/FP16 variants selected by hardware, same file)
- ONNX Runtime GPU (`onnxruntime-gpu`) - Inference backend for InsightFace/YOLO ONNX exports; provider selection (`CUDAExecutionProvider`, `CoreMLExecutionProvider`, `ROCMExecutionProvider`) is hardware-detected
- OpenVINO (`openvino>=2024.0.0`) - CPU/Intel-optimized inference path for PPE YOLO model (`best_openvino_model` in `backend/models/`)
- MediaPipe (`mediapipe`) - Holistic landmarker (`backend/camera/model_manager.py::get_mp_holistic`); face-mesh/hands solutions are explicitly disabled (removed from MediaPipe 0.10.x Python API) with geometric cropping used as a fallback in `backend/camera/vision_service_zones.py`
- OpenCV (`opencv-python`) - Frame/image processing throughout `backend/camera/`
- PyTorch (`torch`, `torchvision`, `torchaudio`, CUDA 12.4 build) - Installed separately in `Dockerfile` for Ultralytics/MediaPipe/embedding backends
- `lapx` - Linear-assignment solver used by ByteTrack (person re-ID matching)
- pgvector (`pgvector`, PostgreSQL extension `vector`) - Vector embeddings storage (face embeddings, semantic memory) — extension is created at startup in `backend/main.py`
- `sentence-transformers` - Text embeddings (used by `backend/services/memory/` and `backend/services/retrieval/vector_retriever.py`)
- EasyOCR (`easyocr`) - OCR, likely for document/report scanning
- PyMuPDF (`pymupdf`) - PDF parsing

**AI / LLM (Backend):**

- Local GGUF LLMs via `llama-cpp-python` - `MedGemma.gguf` (clinical summarization, with `mmproj-F16.gguf` for vision via `Llava15ChatHandler`) and `Qwen3.gguf`/`Qwen31.gguf` (general hospital security/ops Q&A), managed by `backend/services/llm_manager.py::LLMManager` with hardware-aware engine selection (`vLLM` on Nvidia GPU, `mlx-lm` on Apple Silicon, `llama-cpp-python` fallback — though only the llama-cpp path is actually implemented in `_load_specific_model`)
- Google Gemini (`google-genai` SDK) - Cloud LLM client configured in `backend/main.py` from `GEMINI_API_KEY`; used as `client = genai.Client(...)` (not yet wired into a specific endpoint in the reviewed code beyond client construction)
- `faster-whisper` - Speech-to-text for consultation audio (`backend/main.py::transcribe_audio`, `/api/consultations` audio upload), auto-selects CUDA/float16 or CPU/int8 device
- `kittentts` - Text-to-speech engine (paired with `pyttsx3` as a fallback/alternate TTS)

**Real-time / Media:**

- `aiortc` (>=1.8.0) + `av` (>=12.0.0) - WebRTC server-side peer connections for live camera streaming (`backend/camera/webrtc.py`, `backend/camera/routes.py::webrtc_offer`) and patient/doctor video calls (`backend/routers/calls.py`)
- `websockets` - Backend WebSocket support (staff live view, indoor tracking broadcast in `backend/indoor_tracking/hub.py`, security/events routers)
- `flutter_webrtc` (^1.5.2) - Flutter-side WebRTC client for camera streaming and PTM/video calls
- `web_socket_channel` (^3.0.0) - Flutter WebSocket client

**Auth (Backend):**

- `pyjwt` - JWT issuing/verification (`backend/routers/auth.py`, `SECRET_KEY`/`ALGORITHM = "HS256"`)
- `bcrypt` / `passlib` - Password hashing (`bcrypt.hashpw`/`bcrypt.checkpw` in `backend/routers/auth.py`)
- `cryptography` - Used for RFID card token AES-256-GCM encryption (per `backend/routers/rfid.py` docstring)
- `python-jose`/OAuth2PasswordBearer (FastAPI security) - `oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login")`

**Testing:**

- No dedicated test framework dependency found in `backend/requirements.txt` (no `pytest` listed, though `backend/.pytest_cache/` exists, implying pytest is installed ad hoc/via a dev environment not captured in requirements.txt)
- `backend/test_indoor_tracking.py` - Standalone test script for indoor tracking fusion/gating logic
- `flutter_source/test/` - Flutter widget/unit tests; `flutter_test` + `flutter_lints` (^3.0.0) as dev dependencies

**Build/Dev:**

- `python-dotenv` - Loads `backend/.env` (`load_dotenv(override=False)` in both `backend/main.py` and `backend/database.py`)
- `psutil` - System resource monitoring (likely hardware/queue health checks in camera workers)

## Key Dependencies

**Critical:**

- `fastapi`, `sqlalchemy`, `psycopg2-binary` - Core web + DB stack
- `insightface`, `onnxruntime-gpu`, `ultralytics` - Face-recognition attendance and PPE/person-detection computer vision, the app's core hospital-operations feature
- `llama-cpp-python`, `google-genai` - Dual LLM strategy: local GGUF models for clinical/ops chat, cloud Gemini client available for other AI tasks
- `aiortc` - Enables both live camera AI streaming and patient-doctor video calls over WebRTC

**Infrastructure:**

- `pgvector` (Python + Postgres extension) - Vector similarity search backing embeddings (face/semantic memory)
- `alembic` - Versioned schema migrations (currently coexisting with `create_all()` bootstrap and several one-off patch scripts: `backend/alter_db.py`, `backend/backfill_db.py`, `backend/migrate_db.py`)

## Configuration

**Environment:**

- `backend/.env` (present, git-ignored, not read for values) / `backend/.env.example` documents required variables:
  - `DATABASE_URL` - PostgreSQL connection string
  - `SECRET_KEY` - JWT signing secret; app logs a hard warning and falls back to an insecure default string if unset (`backend/routers/auth.py`)
  - `GEMINI_API_KEY` - Google AI Studio key for Gemini client
  - `HOME_ASSISTANT_URL` / `HOME_ASSISTANT_TOKEN` - Documented as an optional Home Assistant integration in `.env.example`, but no corresponding usage found anywhere in `backend/` source (reserved/future integration, not currently wired up)
  - `RFID_STATION_DEVICE_KEY` - Pre-shared key for the one physical RFID enrollment station (ESP32 + RC522), auto-provisions a matching `RfidDevice` row at startup (`backend/routers/rfid.py::ensure_fixed_station`, called from `backend/main.py` lifespan)
- Flutter: `--dart-define=MAPBOX_KEY=pk.xxxxx` build-time define for Mapbox (`flutter_source/lib/main.dart`); `flutter_source/lib/network/environment.dart` defines `Local`/`Staging`/`Production` environment configs with hardcoded/placeholder staging & prod URLs (`staging-api.example.com`, `api.example.com`) and a LAN-IP-based local config

**Build:**

- `Dockerfile` (repo root) - Single-container build: CUDA base image + Python deps + PyTorch (CUDA 12.4 wheels) + a from-source Flutter SDK checkout (`flutter config --enable-web`), exposes ports 8000 and 8080
- `docker-compose.yml` - Two services: `medical-db` (`pgvector/pgvector:pg16` image, mapped to host port 5433) and `medial-agent` (the app container, `network_mode: host`, NVIDIA GPU reservation, 8GB shared memory)
- `backend/alembic.ini` + `backend/alembic/` - Migration environment
- `flutter_source/analysis_options.yaml` - Dart lint rules

## Platform Requirements

**Development:**

- Python 3.14 virtualenv(s) at `backend/.venv` and `backend/.venv-glb`
- Flutter SDK (stable channel) for `flutter_source/`
- Local PostgreSQL with `pgvector` extension (or the Dockerized `pgvector/pgvector:pg16` image)
- NVIDIA GPU strongly preferred for CV/LLM inference (CUDA 12.4/12.6), with fallback code paths for Apple Silicon (CoreML/MPS) and CPU-only (OpenVINO/int8)

**Production:**

- Single Docker container (`Dockerfile`/`docker-compose.yml`) run with `network_mode: host`, NVIDIA runtime, and X11/display passthrough (suggests the deployment target is an on-prem GPU box with a physically attached display, not a typical headless cloud VM) — consistent with an on-premise hospital-operations appliance rather than a cloud SaaS deployment
- PostgreSQL 16 with `pgvector` extension as the persistent datastore

---

*Stack analysis: 2026-09-14*
