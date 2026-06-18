# Healthcare Operations Copilot - AI Camera System

This repository contains a full-stack system consisting of a Python/FastAPI backend and a Flutter frontend. The application is an AI-powered surveillance and staff management system that connects to RTSP IP cameras (e.g., TP-Link Tapo), performs real-time facial recognition using InsightFace, and logs staff attendance automatically.

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
