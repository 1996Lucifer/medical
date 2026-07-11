# Backend ML Optimization Guide

## Current Architecture

The backend currently loads the following models simultaneously into a
single Python process running on CPU:

-   InsightFace (Face Recognition)
-   YOLOv8n (Equipment Detection)
-   YOLOv8n-Pose (Fall Detection)
-   YOLOv8n-PPE (Mask/Glove Detection)
-   KittenTTS (Text-to-Speech)

While functional, this architecture increases startup time, memory
consumption, and CPU contention.

------------------------------------------------------------------------

# Recommended Optimizations

## 1. Lazy Load Models (Highest Priority)

### Problem

Every model is loaded during application startup, even if it is never
used.

### Solution

Load a model only when it is requested for the first time, then keep it
in memory for reuse.

### Benefits

-   Much faster startup
-   Lower idle RAM usage
-   Unused models consume no memory

------------------------------------------------------------------------

## 2. Centralized Model Manager (Singleton)

### Problem

Different services may create duplicate instances of the same model.

### Solution

Implement a single `ModelManager` responsible for loading and providing
shared model instances.

### Benefits

-   One copy of each model
-   Easier lifecycle management
-   Reduced memory usage

------------------------------------------------------------------------

## 3. Separate Worker Processes

### Problem

All inference runs inside one Python process.

### Solution

Run each major component as an independent worker:

-   Face Recognition Worker
-   Equipment Detection Worker
-   PPE Detection Worker
-   Pose Detection Worker
-   TTS Worker

### Benefits

-   Better CPU utilization
-   Crash isolation
-   Independent scaling
-   Parallel execution

------------------------------------------------------------------------

## 4. Shared Detection Pipeline

### Problem

Each YOLO model processes the same image independently.

### Solution

Perform object detection once and reuse the detected regions for
downstream models.

### Benefits

-   Eliminates duplicate preprocessing
-   Reduces inference cost
-   Improves throughput

------------------------------------------------------------------------

## 5. Reduce Input Resolution

### Problem

Processing full HD images wastes CPU resources.

### Solution

Resize frames before inference.

Recommended sizes:

-   640×640
-   512×512

### Benefits

-   Lower memory usage
-   Faster inference
-   Minimal accuracy loss for most scenarios

------------------------------------------------------------------------

## 6. Quantize Models

### Problem

FP32 models consume unnecessary memory.

### Solution

Convert supported models to INT8.

### Benefits

-   Smaller model size
-   Lower RAM consumption
-   Faster CPU inference

------------------------------------------------------------------------

## 7. Standardize on ONNX Runtime

### Problem

Different frameworks introduce overhead.

### Solution

Convert supported models to ONNX and run them through ONNX Runtime.

### Benefits

-   Unified inference engine
-   Better CPU optimization
-   Lower memory footprint

------------------------------------------------------------------------

## 8. Use OpenVINO (Intel CPUs)

### Problem

Generic CPU execution is not fully optimized.

### Solution

Deploy ONNX models using OpenVINO when running on Intel processors.

### Benefits

-   Significant CPU acceleration
-   Reduced latency
-   Better resource utilization

------------------------------------------------------------------------

## 9. Parallel Inference

### Problem

Models execute sequentially.

### Solution

Use worker pools or executors to run independent tasks concurrently.

### Benefits

-   Better multi-core utilization
-   Reduced overall processing time

------------------------------------------------------------------------

## 10. Cache Expensive Results

### Problem

The same face is processed repeatedly across consecutive frames.

### Solution

Reuse embeddings and inference results until the tracked object changes.

### Benefits

-   Lower CPU usage
-   Faster response time

------------------------------------------------------------------------

## 11. Track Instead of Detect

### Problem

Detection and recognition run on every frame.

### Solution

Use an object tracker (e.g. ByteTrack or BOT-SORT) and perform heavy
inference periodically.

### Benefits

-   Fewer expensive inference calls
-   Improved throughput
-   Stable object identities

------------------------------------------------------------------------

## 12. Asynchronous Processing Queues

### Problem

One slow task blocks the entire pipeline.

### Solution

Separate processing stages using queues.

Example:

Camera → Detection → Recognition → Notifications → TTS

### Benefits

-   Non-blocking architecture
-   Better scalability
-   Improved responsiveness

------------------------------------------------------------------------

## 13. Memory-Mapped Models

### Problem

Large models occupy RAM immediately.

### Solution

Use memory mapping where supported.

### Benefits

-   Reduced peak memory usage
-   Faster model loading

------------------------------------------------------------------------

## 14. Batch Similar Requests

### Problem

Each request is processed independently.

### Solution

Batch multiple inference requests together whenever possible.

### Benefits

-   Higher throughput
-   Better CPU efficiency

------------------------------------------------------------------------

## 15. Isolate Text-to-Speech

### Problem

TTS competes with computer vision workloads.

### Solution

Move KittenTTS into a dedicated worker or service.

### Benefits

-   Vision pipeline remains responsive
-   Easier scaling
-   Independent deployment

------------------------------------------------------------------------

# Recommended Production Architecture

``` text
                FastAPI
                   │
        ┌──────────┼──────────┐
        │          │          │
        ▼          ▼          ▼
 Frame Queue   Audio Queue  Event Queue
        │          │
        ▼          ▼
 Detection     TTS Worker
    │
    ▼
 Object Tracker
    │
 ┌──┼───┐
 ▼  ▼   ▼
Face PPE Pose
    │
    ▼
 Results API
```

------------------------------------------------------------------------

# Implementation Priority

  Priority   Recommendation              Expected Impact
  ---------- --------------------------- -----------------
  1          Lazy Loading                Very High
  2          Singleton Model Manager     Very High
  3          ONNX Runtime / OpenVINO     Very High
  4          Separate Worker Processes   High
  5          Shared Detection Pipeline   High
  6          Object Tracking             High
  7          INT8 Quantization           High
  8          Async Queues                Medium
  9          Caching                     Medium
  10         TTS Isolation               Medium

------------------------------------------------------------------------

# Final Recommendation

For the current backend, the best combination of improvements is:

1.  Implement lazy loading.
2.  Introduce a singleton ModelManager.
3.  Convert supported models to ONNX Runtime.
4.  Use OpenVINO when deployed on Intel CPUs.
5.  Separate inference into worker processes.
6.  Add object tracking to reduce repeated inference.
7.  Quantize models to INT8 where accuracy remains acceptable.
8.  Move KittenTTS into its own worker.
9.  Use asynchronous queues between processing stages.

These changes will substantially reduce memory usage, improve CPU
utilization, shorten startup time, and increase overall throughput while
keeping the system easier to maintain.
