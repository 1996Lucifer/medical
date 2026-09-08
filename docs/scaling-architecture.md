# Multi-Building Camera Scaling — Architecture Design

## Scope confirmed with the client

- One deployment per hospital (no shared multi-tenant platform, no
  `Site`/`Institution` data model needed — `models.py:526` `SiteConfig` stays
  a singleton).
- "Multi-site" for this order means: one hospital, potentially multiple
  physical buildings/wards, each with its own local network and cameras, all
  feeding one shared backend/DB/dashboard for that hospital.
- Needs to also handle the simpler case (many cameras, one building) as a
  special case of the same design — not two different architectures.

## Why the current design can't do this

`backend/camera/vision_worker.py`'s `VisionProcessManager` (lines 160-315)
pools inference across `multiprocessing.Process` subprocesses on **one
machine**, with frames handed to each subprocess via
`multiprocessing.shared_memory` (lines 46-47, 254-255). Shared memory only
works between processes on the same OS host — there is no way to point a
worker at a GPU box in a different building without replacing this IPC layer.
`_default_pool_size()` (line 124) already defaults to more workers on CPU
than GPU profiles, but "more workers" today always means "more subprocesses
on this one server."

## Proposed design

Replace the shared-memory IPC between `worker.py`'s `CameraWorker` (frame
capture, one per camera, RTSP) and the inference workers with a **message
broker**, so inference processes can run on the same machine (today) or on
additional machines in other buildings (when capacity is added), without
`CameraWorker` needing to know or care where inference actually runs.

**Broker: Redis Streams.** Lightweight, self-hostable, no new heavyweight
infra, and Streams give exactly what's needed for free: durable delivery,
and consumer groups so N inference workers pull from the same stream with
automatic load-balancing (no custom scheduling code needed to replace
`_least_loaded_worker()`).

**Frame transport.** JPEG-encode the frame (the codebase already does this
for the live video stream) and `XADD` it to a per-camera Redis stream
instead of writing into a shared-memory segment. Inference workers `XREADGROUP`
from the streams they're assigned, run the existing
`vision_service_zones.VisionServiceZones.process_frame()` unchanged, and
publish results (small JSON: `face_events`/`ppe_events`/etc., not the frame)
back to a results stream that `CameraWorker` reads instead of
`vision_process_manager.pop_result()`.

**Deployment shape per building.**
- Central: FastAPI backend + Postgres + Redis (or Redis reachable over the
  hospital's VPN/LAN from every building).
- Per building: one or more inference-worker processes (`docker-compose up
  --scale vision-worker=N`), ideally colocated with that building's GPU box
  so face/PPE inference stays low-latency and doesn't cross the network for
  every frame — only compressed frames and small result payloads cross
  building boundaries, not raw video.
- `CameraWorker` (RTSP capture) can run wherever the camera's network is
  reachable from — same building as its cameras, reporting frames into the
  shared Redis.

**What does NOT need to change:** `vision_service_zones.py`'s actual
detection/tracking/PPE-rule logic, `worker.py`'s drawing/smoothing/alert
code, the DB schema. This is purely an IPC-layer swap underneath the
existing `VisionProcessManager` public API (`start_process`,
`register_camera`, `process_frame_async`, `pop_result`) — every other file
that calls it stays untouched.

## Why this isn't implemented yet

This session just spent significant effort hardening the exact camera
pipeline this touches (face bbox accuracy, PPE detection confirmation
streaks, tamper alerts) — rewriting its IPC layer without a live multi-
machine environment and a real Redis instance to test against would be
guessing at a distributed-systems change, not verifying one. This doc is the
scoped design; implementation should happen against a real staging
environment with at least two machines to prove frames genuinely flow
cross-network before it's called done.

## Effort estimate

- Redis IPC swap in `vision_worker.py` + `worker.py` result consumption: the
  bulk of the work, touches the two files above plus `docker-compose.yml`.
- Per-building deployment docs + `docker-compose` profile for a
  worker-only node.
- Staging validation against ≥2 machines before considering this done.

Medium-to-large — real days, not hours; scope it as its own line item
separate from the auth/migration/onboarding fixes already shipped this
session.
