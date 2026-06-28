# Healthcare Operations & Clinical Copilot - Medical Software & On-Device AI

This repository contains a full-stack system consisting of a Python/FastAPI backend and an offline-first Flutter frontend. The application serves two primary roles for a hospital:
1. **Clinical Copilot (Frontend-Heavy)**: An on-device AI assistant for doctors. It uses local multimodal AI (MediaPipe Audio, Gemini Nano/Gemma 4) for offline SOAP note generation, medical report analysis, and hybrid syncing to a private server.
2. **Operations Copilot (Backend-Heavy)**: An AI-powered surveillance system that connects to RTSP IP cameras, performs real-time facial recognition (InsightFace), tracks staff/equipment, and enforces safety compliance (PPE).

## Architecture Overview

### 1. Backend (Python / FastAPI)
The backend is located in the `backend/` directory and is built using FastAPI, SQLAlchemy (SQLite), and OpenCV/InsightFace for computer vision.

#### Key Components:
- **`main.py`**: The entry point for the FastAPI application. Sets up routes and CORS.
- **`database.py` & `models.py`**: SQLAlchemy setup and ORM models. 
  - `Camera`: Stores RTSP camera details (name, location, rtsp_url).
  - `Staff`: Stores staff details (name).
  - `StaffPhoto`: Stores multi-angle reference photos for a staff member (label: front, left, right, etc.) and their extracted face embeddings (stored as JSON bytes).
  - `Attendance`: Logs staff appearances. Operates on a "session" basis (tracks `entry_time`, `last_seen`, and `exit_time`). A new session is created if a staff member hasn't been seen for 5 hours.
- **`camera/vision_service.py`**: Handles facial detection, recognition, and feature extraction (age/gender). Uses `insightface` with ONNX models (`buffalo_l`). It computes cosine similarity between real-time face embeddings and the reference embeddings stored in the database.
- **`camera/camera_worker.py`**: A background threading worker that connects to an RTSP stream via OpenCV. It captures frames, passes them to `VisionService`, draws bounding boxes and metadata (name, confidence, age, gender) on the frame, encodes it as JPEG, and pushes it to connected WebSocket clients. It also throttles database writes for attendance tracking (once every 30 seconds per person).
- **`camera/routes.py`**: Contains all REST and WebSocket endpoints:
  - `GET /api/ws/camera`: WebSocket endpoint for frontend clients to receive the annotated live MJPEG stream. Can connect via `camera_id` or raw `camera_url`.
  - `/api/cameras`: CRUD operations for RTSP camera sources.
  - `/api/staff`: CRUD operations for staff members. Includes uploading primary photos and extra angle photos.
  - `/api/staff/{id}/photos`: Management of multi-angle photos for better recognition.
  - `/api/attendance`: Retrieves the attendance logs, and manual checkout endpoints.

### 2. Frontend (Flutter)
The frontend is located in the `flutter_source/` directory.

#### Key Components:
- **`lib/main.dart`**: Sets up the `MaterialApp` and a `BottomNavigationBar` containing the main app tabs (Consultation, AI Camera, Settings).
- **`lib/camera/camera_screen.dart`**: 
  - Connects to the WebSocket endpoint to display the live annotated camera feed.
  - Allows quick switching of the active camera source.
  - Displays a real-time Attendance list panel on the right side, showing Entry Time, Last Seen Time, Exit Time, and the camera location.
  - Allows manual checkout of staff.
- **`lib/settings/settings_screen.dart`**: Administrative dashboard containing:
  - **Manage Cameras**: List, Add, Edit, and Delete RTSP camera sources.
  - **Manage Staff**: List, Add, Edit, and Delete staff members.
  - **Manage Photos (Staff)**: Upload multiple angle photos (side, angled, with mask/glasses) to improve the Vision Service's recognition accuracy. Allows deleting old/bad reference photos.

## Current State & Features Implemented
1. **Multi-Angle Facial Recognition**: The system successfully stores multiple face embeddings per person. When a face is detected in the video stream, it compares the face against all stored angles and picks the highest match.
2. **Session-Based Attendance**: Instead of logging a row every time a face is seen, the system logs an `entry_time`. As long as the person is seen again within 5 hours, it updates the `last_seen` timestamp. If 5 hours pass, the next detection creates a new row.
3. **Hardware Acceleration Support**: The VisionService attempts to use CPU by default, but logs show it is capable of picking up CoreML/CUDA if the environment is properly configured.
4. **WebSocket Broadcasting**: The backend can handle multiple frontend clients viewing the same camera stream simultaneously without pulling the RTSP stream multiple times, thanks to the `CameraWorker` pub-sub queue design.
5. **Full CRUD Settings**: The Flutter app contains a fully functional settings UI for maintaining the database of staff and cameras.

## How to Run
- **Backend**: Navigate to `backend/` and run `./start.sh` (or `uvicorn main:app --host 0.0.0.0 --port 8000 --reload`).
- **Frontend**: Navigate to `flutter_source/` and run `flutter run` (supports macOS desktop, iOS, Android, and Web).

## Important Technical Nuances for AI Context
- The system heavily relies on `SessionLocal()` instances spawned manually inside the `CameraWorker` background thread, rather than FastAPI's `Depends(get_db)` because background threads do not have access to FastAPI's request lifecycle.
- When sending face photos to the backend (`/api/staff?name=...` or `/api/staff/{id}/photo`), the file is sent as `multipart/form-data`. The backend reads the file, detects the face via `VisionService`, extracts the embedding, and converts the NumPy embedding to JSON before saving it to the SQLite database.
- TP-Link Tapo cameras require the username and password to be raw in the RTSP URL, e.g., `rtsp://user:pass@ip:554/stream1`. Special characters in the password are supported but must be formatted properly.

## Roadmap / Future Enhancements

The current system covers the hard infrastructure: RTSP ingestion, multi-client WebSocket broadcasting, vector-based face matching, and session-aware attendance logging. The items below are grouped by category so it's clear which are safe incremental improvements and which are bigger capability decisions that need a deliberate call before building.

### A. Reliability & Accuracy (low risk, do anytime)
- **Recognition confidence tuning**: Enforce a proper rejection threshold so a stranger isn't misattributed to the closest-matching staff member. Log "unknown face detected" events as their own category instead of silently dropping or misassigning them.
- **RTSP reconnect handling**: Verify `camera_worker.py` retries gracefully on stream drops rather than letting the background thread die silently. Add a heartbeat/health check per camera.
- **Multi-face-in-frame handling**: Confirm the system correctly produces separate bounding boxes and separate attendance entries when 2+ staff are visible simultaneously.
- **Liveness / anti-spoofing**: A single-frame embedding match can potentially be fooled by a photo held up to the camera. This is a real open problem, not a one-line fix — worth evaluating a dedicated liveness-detection approach (e.g., a depth/motion-based or blink-based check) rather than an ad hoc heuristic.
- **Embedding storage at scale**: Embeddings are currently stored as JSON bytes in SQLite with (presumably) a linear cosine-similarity scan per frame. Fine at small scale; past roughly 50-100 staff x multiple angles, consider an in-memory cache of all embeddings at startup, and/or a proper vector index (FAISS, `sqlite-vec`) instead of a per-frame linear scan.

### B. Analytics & Reporting (low risk, high visible value)
- **Attendance analytics dashboard**: Daily/weekly summaries (total hours, late arrivals, early departures) built from existing `Attendance` rows — mostly an aggregation query + frontend view away.
- **Camera-offline alerts**: Notify admins when a registered camera's RTSP stream drops, using the heartbeat check above.
- **Unknown-face alerts**: Webhook/push notification when an unrecognized face is seen, especially during off-hours.

### C. Event Correlation Layer (medium effort, foundational)
- Build a queryable event timeline/graph: `person -> camera -> timestamp -> action` (entered, exited, lingered, unknown-face-flagged), rather than treating each camera's attendance log as a silo.
- Decide explicitly how a handoff between cameras is treated — e.g., a staff member walking from Camera A's view into Camera B's — as one continuous session vs. an exit + new entry. Currently this is likely incidental rather than designed behavior.
- This layer is worth building before the items in section D, since the LLM query interface and anomaly detection are much easier on top of a structured event log than on raw per-camera rows.

### D. Conversational / Agentic Layer (medium effort, high leverage)
- **Natural-language query over logs**: An LLM layer that translates plain-English questions ("Who was in Camera 2's view between 2-4pm yesterday?") into queries against the existing `Attendance`/`Staff` tables via function calling into the existing FastAPI endpoints. This reuses existing data and endpoints rather than requiring new ML.
- **Automatic shift/anomaly digests**: LLM-generated daily summaries (irregular check-ins, camera downtime, unusual shift overlaps) instead of admins reading raw logs.
- **Chat tab in the Flutter app**: A conversational interface as an alternative to digging through the Settings CRUD screens.
- **Predictive staffing-gap analysis**: Time-series analysis on existing attendance history to flag recurring understaffed windows (e.g., a ward consistently thin between 2-4pm).

### E. Behavioral & Compliance Monitoring (bigger capability decision — needs sign-off before building)
These move the system from "attendance logger" to "continuous behavioral monitoring of healthcare staff," which is a materially bigger step in scope than anything above. They are technically reasonable extensions of the existing pipeline (same camera feed, an additional model running alongside InsightFace), but each one should go through an explicit privacy/HR/legal decision before implementation, not be added casually:
- **PPE/compliance detection**: Object detection (e.g., YOLO) on the same frame to flag missing mask/gloves/gown in zones that require it.
- **Hand-hygiene zone monitoring**: Detect whether staff pause at a sanitizer station before entering a ward.
- **Fall/incident detection**: Pose estimation (e.g., MediaPipe) on the same feed to detect a person collapsing in a hallway and trigger an alert. This one is safety-critical rather than compliance-oriented, and arguably has the clearest justification of this group.
- **Patient-related tracking**: Any feature that touches patient presence or movement — even without identifying a patient by name — brings in health-data regulation (HIPAA-equivalent depending on jurisdiction; India's DPDP Act) and should not be built without that review.

### F. Platform & Access Control (longer horizon)
- **Role-based access control**: Add admin authentication; currently anyone with the Flutter app can manage staff/cameras and view attendance.
- **Explicit hardware acceleration wiring**: CoreML/CUDA are available but currently picked up via auto-detection. As camera count grows, explicitly configuring this (and/or batching frames across streams) will matter for scaling beyond a single server's CPU budget.
- **Privacy/compliance layer**: Since this system stores biometric data (face embeddings) on staff, plan for: consent records, a defined retention/deletion policy for photos and embeddings, and audit logs of who accessed attendance data. Relevant regardless of which features above get built, given the biometric data already being stored today.

**Suggested build order for maximum leverage per unit effort**: A and B items first (low risk, immediate value) -> C, the event correlation layer (foundation for everything after) -> D, the LLM query interface (high perceived value, reuses existing infrastructure) -> a single flagship item from E only after an explicit privacy/compliance decision -> F as the system matures toward real deployment.