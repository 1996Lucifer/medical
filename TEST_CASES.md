# System Test Cases & Quality Assurance

This document tracks all manual and automated test cases for the Healthcare Operations Copilot, ensuring that our "no margin for error" requirement is met across all phases.

## Phase 1 & 2: Core Vision & Attendance (Completed)

| Test ID | Component | Description | Status |
|---------|-----------|-------------|--------|
| TC-1.1 | Vision Service | Verify face detection accurately draws bounding boxes on valid faces. | ✅ Pass |
| TC-1.2 | Recognition | Ensure multiple reference photos for a staff member yield >0.5 confidence. | ✅ Pass |
| TC-1.3 | Anti-Spoofing | Verify face bounding box < 60x60 is rejected (Liveness mitigation). | ✅ Pass |
| TC-2.1 | Attendance | Ensure entering a camera view creates a new Session if gap > 5 hours. | ✅ Pass |
| TC-2.2 | Attendance | Ensure lingering in the same camera view simply updates `last_seen`. | ✅ Pass |
| TC-2.3 | Analytics | Dashboard accurately displays timezone-aware bar chart of total hours. | ✅ Pass |

## Phase 3: Reliability, Compliance & Security (Completed)

| Test ID | Component | Description | Status |
|---------|-----------|-------------|--------|
| TC-3.1 | Correlation | `GET /api/events/timeline` correctly resolves a camera handoff (AreaTransition) into a contiguous session. | ✅ Pass |
| TC-3.2 | Security | `/api/staff` and `/api/attendance` return `401 Unauthorized` without a JWT token. | ✅ Pass |
| TC-3.3 | RBAC | Login screen accepts `admin`/`admin` and successfully routes to Dashboard. | ✅ Pass |
| TC-3.4 | Compliance | Face detected without a mask in `is_restricted` camera triggers a High-Severity `PPE Violation` SecurityAlert. | ✅ Pass |

## Phase 4: Clinical Copilot & On-Device AI Integration (Completed)

| Test ID | Component | Description | Status |
|---------|-----------|-------------|--------|
| TC-4.1 | Consultation UI | Flutter app correctly starts and stops microphone recording on Consultation Screen. | ✅ Pass |
| TC-4.2 | Backend AI | `/api/consultations` successfully accepts audio file, queries Gemini 2.5 Flash, and returns structured SOAP Note. | ✅ Pass |
| TC-4.3 | Local Storage| `flutter_secure_storage` securely encrypts and stores the JSON response payload on the device. | ✅ Pass |
| TC-4.4 | Offline Access| Consultation History list loads and displays previously generated SOAP notes successfully from local cache. | ✅ Pass |

## Phase 5: Medical Report Analysis (Completed)

| Test ID | Component | Description | Status |
|---------|-----------|-------------|--------|
| TC-5.1 | Camera UI | Consultation Screen features a secondary Camera button that prompts the device image picker. | ✅ Pass |
| TC-5.2 | Backend AI | `POST /api/analysis/report` accepts image multipart, queries Gemini 2.5 Flash, and returns structured JSON (Key Findings, Abnormalities). | ✅ Pass |
| TC-5.3 | Local Storage| `flutter_secure_storage` encrypts the report analysis JSON just like the audio notes, and displays them interchangeably in the history list. | ✅ Pass |
