# Master Project: Medical Software & On-Device AI

## Project Vision
Initialize a production-grade Flutter application for doctors and hospital management. The app focuses on offline-first functionality with automated "Hybrid Sync" to a private server and deep integration with on-device AI for medical reasoning.

## Core Architecture
- **Framework:** Flutter
- **Pattern:** Clean Architecture (Presentation, Domain, Data layers)
- **State Management:** Riverpod
- **Storage:** Local encryption for SQLite/Hive using flutter_secure_storage.

## Local Multimodal AI ("Ears" & "Eyes")
- **Audio:** MediaPipe for local ASR (Speech-to-Text).
- **Vision/Reasoning:** 
    - Android: Gemini Nano (via AICore).
    - iOS: Gemma 4 (via Google AI Edge).
- **Use Cases:** SOAP note generation, medical report/photo analysis, and inventory management.

## Hybrid Data Strategy
1. **Phase 1 (Active):** Immediate upload to Gemini File API for high-level reasoning (48-hour temporary storage).
2. **Phase 2 (Permanent):** Simultaneous upload to Private Server (Supabase/Appwrite) for permanent history.
3. **Phase 3 (Retrieval):** Fetch "External URLs" from private server back into Gemini for historical comparisons.

## Technical Dependencies
- `google_generative_ai`
- `mediapipe_audio`
- `riverpod`
- `flutter_secure_storage`
- `dio` (for server sync)

## Planned Infrastructure
- **VisionService:** Logic for dual-upload (File API + Private Server).
- **Security:** AES encryption for local patient records.