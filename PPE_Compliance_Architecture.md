# Hospital AI PPE Compliance System
## Model-Agnostic Vision Language Model (VLM) Architecture

**Version:** 1.1  
**Status:** Recommended Architecture  
**Deployment:** CPU (Demo) → GPU (Production)  
**Design Goal:** Scalable, Model-Agnostic, Multi-Camera PPE Compliance System

---

# Objective

The objective of this system is **not** to detect gloves or masks in every frame.

Instead, the objective is:

> **Verify that an authorized healthcare worker is compliant with hospital PPE requirements before entering a restricted zone and continue monitoring for violations.**

This converts an unreliable object detection problem into a deterministic workflow verification system.

---

# Design Philosophy

Traditional approach:

```
Every Frame
↓
Detect Person
↓
Detect Mask
↓
Detect Gloves
↓
Repeat Forever
```

Problems:
- High CPU/GPU usage
- Frequent false positives
- Frequent false negatives
- Impossible under occlusion
- Difficult under different camera angles

Proposed approach:

```
Person Approaches ICU
↓
Identify Person
↓
Verify PPE Once
↓
Store Compliance Status
↓
Track Person
↓
Only Re-verify When Necessary
```

This significantly improves reliability while reducing computation.

---

# Why Generic PPE Detection Fails

Models such as YOLO PPE, Generic PPE datasets, and Object detectors struggle because:
- Gloves occupy very few pixels.
- Hands frequently rotate.
- Gloves become occluded while working.
- Medical gloves differ from industrial PPE.
- Side and rear views hide masks.
- Lighting conditions vary significantly.

No computer vision model can detect objects that are not visible.
Therefore, expecting 100% frame-by-frame PPE detection from a single RGB camera is unrealistic.

---

# Proposed Architecture

```
                    Camera Stream
                          │
                          ▼
                 YOLO11n Person Detector
                          │
                          ▼
                    ByteTrack Tracker
                          │
                          ▼
                  InsightFace Recognition
                          │
                ┌─────────┴─────────┐
                │                   │
                ▼                   ▼
        MediaPipe Face        MediaPipe Hands
                │                   │
                ▼                   ▼
           Face Crop           Hand Crop
                │                   │
                └─────────┬─────────┘
                          ▼
              Vision Language Model
                 (Pluggable Module)
                          │
                          ▼
               PPE Verification Engine
                          │
                          ▼
                Compliance Decision
                          │
                          ▼
             Zone Access & Monitoring
```

---

# Recommended Components

## Person Detection
Model: `YOLO11n`
Purpose: Detect people, CPU friendly, GPU accelerated, Lightweight.

## Person Tracking
Model: `ByteTrack`
Purpose: Persistent IDs, Multi-person support, Cross-frame tracking.

## Face Recognition
Model: `InsightFace`
Purpose: Identify staff, Maintain identity across cameras.
Status: ✅ Already integrated.

## Face Localization
Model: `MediaPipe Face Mesh`
Purpose: Precise face cropping, Better mask verification.
Status: ✅ Already integrated.

## Hand Localization
Model: `MediaPipe Hands`
Purpose: Detect hand landmarks, Generate stable hand crops.
Status: ✅ Already integrated.

---

# Vision Language Model (VLM)

The architecture intentionally remains **model-agnostic**. The VLM is used **only during PPE verification**, not continuously.

Current implementation:
`MedGemma GGUF` + `llama-cpp-python` + `mmproj-F16.gguf`

Advantages: Already integrated, Runs locally, CPU compatible, GPU acceleration available later, No additional dependencies.

---

# Future Model Options

The VLM backend can be replaced without changing the overall system. Possible replacements include:
- MedGemma
- Florence-2
- Qwen2.5-VL
- SmolVLM
- MiniCPM-V
- Phi-4 Multimodal

Only the verification module changes. The remainder of the architecture stays identical.

---

# Why Keep MedGemma

Current backend already contains: MedGemma GGUF, mmproj, llama-cpp-python, Existing inference pipeline.
Adding Florence-2 would require: HuggingFace Transformers, Additional model downloads, New inference code, Extra memory usage, Additional maintenance.

Since verification happens only when entering restricted zones, MedGemma's inference speed is sufficient.

Therefore the recommended approach is:
- Keep MedGemma initially.
- Evaluate Florence-2 only if real-world testing demonstrates a measurable improvement.

---

# Vision Verification Pipeline

```
Face Crop ↓ Vision Language Model (MedGemma) ↓ Mask Verification
Hand Crop ↓ Vision Language Model (MedGemma) ↓ Glove Verification
```

---

# Example Verification Prompts

## Mask
`Is this healthcare worker correctly wearing a surgical mask? Answer only: YES NO`

## Left Hand
`Is this left hand wearing a medical examination glove? Answer only: YES NO`

## Right Hand
`Is this right hand wearing a medical examination glove? Answer only: YES NO`

---

# Pluggable VLM Design

Create a common interface.

```python
class VisionVerifier:
    def verify_mask(self, image): pass
    def verify_left_glove(self, image): pass
    def verify_right_glove(self, image): pass
    def verify_full_ppe(self, face_crop, left_hand_crop, right_hand_crop): pass

class MedGemmaVerifier(VisionVerifier):
    ...
```

The rest of the application remains unchanged.

---

# Zone-Based Workflow

Three logical zones are recommended.

```
+---------------------------------------------------+
              Observation Zone
        Person Detection + Tracking
       +-----------------------------+
       |    Verification Zone        |
       | Face Verification           |
       | Mask Verification           |
       | Left Glove Verification     |
       | Right Glove Verification    |
       +-----------------------------+
            Restricted Zone
          ICU / OT / NICU
+---------------------------------------------------+
```

---

# Zone Responsibilities

## Observation Zone
Detect people, Track movement, Recognize identities. No PPE verification.

## Verification Zone
Face camera, Stand still, Raise left hand, Raise right hand. Run: Face recognition, Mask verification, Left/Right glove verification.

## Restricted Zone
Continue tracking, Detect mask removal, Detect unauthorized entry, Generate alerts. Avoid continuous glove detection.

---

# Compliance Engine

Instead of making decisions every frame, store verification results in memory with an expiration. Every camera checks whether the verification remains valid via the token.

---

# Final Recommendation

The system should remain **model-agnostic**.

Current Recommendation: YOLO11n, ByteTrack, InsightFace, MediaPipe Face Mesh, MediaPipe Hands, **MedGemma (Current VLM)**, Compliance Engine, Multi-Camera Zone Management.

Future Recommendation: Replace only the VLM implementation if testing demonstrates better PPE verification (e.g., Florence-2 or Qwen-VL).
