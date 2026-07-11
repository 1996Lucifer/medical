# Medical Agent - Project Context & Coding Guidelines

## 1. Project Overview & Current Architecture
- **Purpose**: A local-first, privacy-focused Medical and Hospital Security AI Assistant.
- **Frontend**: Flutter application (Dart).
- **Backend**: FastAPI (Python) using local ML inference to avoid cloud dependencies.
- **Core AI/ML Stack**:
  - LLMs/VLMs: MedGemma (Multimodal 4B for clinical vision/text), Qwen3 (for database/security context), openai-whisper (for audio transcription).
  - Vision Pipeline: OpenCV, InsightFace (Face Recognition), YOLO/Ultralytics (Object/PPE detection), DeepFace.
  - Compute Engines: `llama-cpp-python`, `transformers`, `mlx-vlm` (for Apple Silicon optimizations).
- **Database**: PostgreSQL with `pgvector` for vector embeddings, accessed via SQLAlchemy.
- **Current State**: Transitioning from external APIs (like Gemini) to 100% local inference running on local hardware (e.g., Apple Silicon/CUDA).

## 2. Containerization & Deployment Directives
**CRITICAL**: This project is designed to be fully containerized via Docker and must be portable across any environment (Linux, macOS, Windows, Android, iOS).
- **Environment Agnostic**: Never hardcode absolute paths. Always use relative paths (`os.path.dirname(__file__)`) or environment variables (e.g., `os.getenv()`).
- **Dependencies**: Ensure all external system binaries (like `ffmpeg`, `libgl1`) required by Python libraries are kept in mind for the future `Dockerfile`. 
- **Local Models**: AI models (`.gguf`, HuggingFace caches) must be loaded from localized directories (`models/`) that can easily be mounted as Docker volumes.
- **Hardware Acceleration**: Code should gracefully detect and fallback between CUDA, Apple Silicon (MPS/MLX/CoreML), and CPU depending on the deployment environment (e.g., check `torch.backends.mps.is_available()`, `torch.cuda.is_available()`).

## 3. Coding Guidelines
- **Python Backend**:
  - Use `typing` hints for all function signatures.
  - Write asynchronous code (`async`/`await`) for I/O operations and FastAPI endpoints to prevent blocking.
  - Implement comprehensive error handling and logging. Avoid silent `try/except: pass` blocks.
- **Frontend (Flutter)**:
  - Adhere to modern Dart(version: 3.12 and above) and Flutter(version: 3.4 and above) styling. Keep the UI layer cleanly separated from business logic (e.g., Provider/Riverpod).
- **AI Implementations**:
  - Favor lightweight, highly quantized models that can fit in limited RAM/VRAM to ensure it runs on standard hardware.
  - Do not use cloud APIs (OpenAI, Gemini, Anthropic) unless explicitly requested. The priority is local privacy and local execution.

## 4. Design & Aesthetics
- **Premium User Experience**: The application UI must feel modern, premium, and highly responsive. Use rich aesthetics, harmonious color palettes, smooth transitions, and dynamic states (hover/active).
