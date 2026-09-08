# MVP Gap Audit — medical_agent

Generated 2026-09-03 via parallel codebase sweep (RBAC/roles, clinical/patient, staff/security/ops).
Every finding below is verified against actual code, not inferred from intent — file:line
references throughout so nothing here needs re-discovery.

## 0. Fix these first — real security holes, not roadmap items

These aren't "missing features," they're live vulnerabilities in what's already built. All are
hours-to-a-day fixes.

**Status: items 1-5 fixed and verified live (2026-09-03)** — see "Fixes applied" below for what
changed and how it was tested. Item 6 (duplicate seed scripts) is still open.

1. ~~**Privilege escalation via `routers/rbac.py`**~~ **FIXED** — zero permission checks on
   role/permission assignment endpoints meant any authenticated user (a freshly-seeded
   nurse/analyst account) could call `POST /api/rbac/assign` to grant themselves SuperAdmin.
2. ~~**`routers/patients.py` has no auth at all**~~ **FIXED** — was a public router.
3. ~~**`routers/agent.py` has no auth at all**~~ **FIXED** — was mounted with no `auth_dep` and
   had its own auth dependency commented out ("Disabled for testing").
4. ~~**`/uploads` static mount has no auth**~~ **FIXED** — was publicly readable, no login,
   wide-open CORS, already exposing incident snapshots.
5. ~~**`security.py`'s `resolve_alert` has no auth**~~ **FIXED** — anyone unauthenticated could
   resolve/dismiss security alerts.
6. **Two contradictory RBAC seed scripts** (`seed_rbac.py` vs `seed_hospital_roles.py`) still
   define different permission taxonomies — whichever ran last silently wins. Not yet fixed; pick
   one, delete the other.

None of these required new features — just adding `Depends(get_current_user)` /
`Depends(require_permission(...))` to existing endpoints, or (still open, #6) deleting a
duplicate file.

### Fixes applied

- **`backend/routers/auth.py`**: added `has_permission(user, permission_name)` and
  `require_permission(permission_name)` — superadmin bypasses all checks; otherwise checks direct
  grants and group grants, reusing the same collection logic already in `/api/auth/me`.
- **`backend/main.py`**: moved `patients.router` and `patient_portal.router` into the
  `dependencies=auth_dep` block (patient_portal had the exact same "no auth on `{patient_id}`"
  problem as patients.py, just not called out as its own line item in the original audit — same
  fix, applied to both). Added `dependencies=auth_dep` to `agent.router`. Gated `rbac.router` with
  `auth_dep + [Depends(require_permission("manage_rbac"))]` — since no one is seeded with that
  permission, only superadmins can reach it today, closing the escalation path. Added
  `AuthenticatedStaticFilesMiddleware`, registered *before* `CORSMiddleware` (so CORS ends up
  outermost and still adds headers to 401s) — validates the same JWT as everywhere else against
  `/uploads/*` before Starlette's `StaticFiles` serves anything.
- **`backend/routers/agent.py`**: removed the now-dead commented-out auth line and unused
  `get_current_user` import (auth is enforced at the router level in `main.py` instead).
- **`backend/routers/security.py`**: added `current_user: models.User = Depends(get_current_user)`
  to `resolve_alert`.
- **`AuthenticatedStaticFilesMiddleware` public exception**: `/uploads/branding/*` (the hospital
  logo, per `routers/site_config.py`'s `_logo_url()`) is explicitly allowlisted as public — it's
  shown on the pre-login screen (`auth/login_screen.dart`) where no token exists yet. Caught this
  by tracing every `Image.network`/`NetworkImage` call site in the Flutter app before assuming a
  blanket gate was safe.
- **Flutter — 9 call sites across 6 files** were making raw, unauthenticated requests to routers
  that are now gated, and would have broken silently without this pass:
  - `patient_portal/{consultations,patient_dashboard,reports_locker,patient_details,upload_report}_screen.dart`
    — switched from raw `http.get`/`http.put`/`http.MultipartRequest` to
    `NetworkManager.instance.{get,put,multipartRequest}`, which already attaches the bearer token.
  - `consultation/consultation_screen.dart` (`_fetchPatients`) — same fix, one `http.get` call.
  - `providers/agent_provider.dart` — `fetchSessions`, session load, `deleteSession`, and
    `fetchHistory` all switched from raw `http.get`/`http.delete` to `NetworkManager.instance`
    (the chat-send call already used `NetworkManager.instance.multipartRequest` correctly).
  - `settings/manage_staff_screen.dart` — added a top-level `_authHeaders()` helper and passed it
    to both `NetworkImage(...)` calls loading staff photos from `/uploads/staff/...`.
  - `admin/super_admin_dashboard.dart` — added the same bearer-token header to the
    `Image.network(...)` call that shows incident snapshots from `/uploads/incidents/...`.

### Verification (live, against a running server + real Postgres DB)

- Confirmed `curl` with no token now gets `401` on `/uploads/*`, `/api/rbac/graph`,
  `/api/patients`, `/api/agent/chat`, and `POST /api/security/alerts/{id}/resolve` — all were
  previously `200`.
- Logged in as the seeded `admin`/`admin` (superadmin) — all five endpoints work normally
  (`200`/`404` as appropriate, never `401`).
- Logged in as the seeded `nurse`/`nurse` (non-superadmin, no `manage_rbac` grant) and replayed
  the exact escalation call from the original finding
  (`POST /api/rbac/assign {"source_type":"user","source_id":1,"target_type":"group","target_id":1}`)
  — now returns `403 Missing required permission: manage_rbac` instead of silently succeeding.
  Confirmed the same nurse account can still hit `/api/patients` and `/api/agent/chat` normally
  (`200`) — the fix is scoped to RBAC management, not a blanket lockout.
- Fetched a real staff photo URL from `/api/staff` and confirmed it's now `401` with no token and
  `200` with the bearer token attached — the exact request shape the updated Flutter
  `NetworkImage(url, headers: _authHeaders())` call now makes — so the auth fix doesn't silently
  break staff photo rendering.
- Confirmed CORS headers (`access-control-allow-origin`, `access-control-allow-credentials`) are
  still present on the `401` response from `/uploads`, so this fails as a clean `401` in the
  Flutter app rather than an opaque CORS error.
- Confirmed `/uploads/branding/*` returns `404` (not `401`) with no token — public as intended —
  while `/uploads/staff/*` still correctly returns `401` with no token.
- Re-verified `/api/patient-portal/dashboard/1`, `/api/agent/sessions`, `/api/rbac/graph`, and
  `/api/patients` all `401` with no token and `200` with a valid superadmin token, confirming the
  Flutter-side fixes above target requests that actually match what the backend now expects.

## 1. Per-role reality check

### SuperAdmin
**Works:** the only role with real enforcement, via hardcoded string check
(`site_config.py:62,90,136`, `current_user.role != "superadmin"`). Flutter UI exists
(`lib/admin/super_admin_dashboard.dart`).
**Gap:** enforcement isn't RBAC-driven at all — it's a string compare, so the entire
RBACGroup/RBACPermission schema (roles, groups, permissions) is populated but decorative outside
this one router.

### Admin
**Works:** `view_settings` permission seeded, RBAC management UI exists in Flutter `lib/settings`.
**Gap:** nothing anywhere checks `view_settings` or any other seeded permission — see §0.1. The
permission system exists in the database but isn't wired into any authorization decision except
the SuperAdmin string check above.

### Doctor / Nurse
**Works, real, end-to-end:** record consultation audio → Whisper transcription → MedGemma
discharge summary → saved (`main.py:190-296`). Upload a medical report image/PDF → MedGemma
extraction of findings/abnormalities → saved (`routers/analysis.py:21-170`, with a manual-confirm
fallback path). Patient list/get/update via real DB queries (`patients.py:22-61`).
**Gap — dead field:** `Consultation.prescription` column exists (`models.py:126`) and is exposed
in the API response, but **no endpoint ever writes to it** — grep confirms zero writers. It's a
column that looks like a feature and isn't one.
**Gap — no auth on the router itself** (§0.2).
**Missing entirely (weeks-scale, not MVP-fast-path):** appointment scheduling (zero grep hits
anywhere in backend/), lab-result/HL7-FHIR integration, e-prescribing workflow, discharge
workflow beyond the text summary (no bed status, no meds reconciliation, no follow-up tracking).

### Patient (patient_portal)
**Works, real:** upload a report, get AI-extracted findings (`patient_portal.py:47-138` — this is
near-duplicate code of `analysis.py`'s pipeline, worth deduping). View own reports/consultations
(`:140-148`). Dashboard vitals chart pulls real historical data from
`MedicalReport.vitals_extracted` (`:150-172`), though it silently swallows JSON parse errors
(`:169`) rather than surfacing a "couldn't read this report" state.
**Missing:** no billing anywhere in this flow (see §2), no appointment booking, no way to message
a doctor/nurse directly (only the AI agent, which currently has no auth — §0.3).

### Security / Facilities
**Works, real, end-to-end:** staff enrollment with face-embedding capture, including a live guided
WebSocket flow (`staff.py:78,133,314,418`) — feeds the live recognition pipeline directly.
Attendance is real (written by `camera/attendance_service.py` from the live pipeline, not a stub).
Equipment tracking is backend-complete (`camera/equipment_service.py` writes real rows,
`routers/equipment.py` reads them) — **but has no Flutter screen at all**, pure API-only feature
today. Security alerts (theft, restricted access, PPE, unauthorized entry) are real, evaluated by
`backend/rules.py`, broadcast over a live WebSocket, and the Flutter security dashboard
(`lib/security/security_dashboard.dart`) consumes real data, not mocks.
**Gap — looks real but isn't:** `SecurityRule` (models.py:384) has full CRUD in
`routers/security.py` with a docstring promising "dynamic natural language rules evaluated by
Gemini" — but `rules.py`'s actual `SecurityRulesEngine` never reads from this table at all; every
check is hardcoded Python. A facility admin can write and save a custom security rule through the
UI today, and it will silently do nothing. This is the single most convincing-looking fake feature
in the product.
**Gap — alerts don't reach anyone off-screen:** only one alert type (`_check_unknown_face_offhours`,
`rules.py:120-144`) posts to an external webhook (Slack-style). The other four alert types (theft,
restricted access, PPE, unauthorized entry) only broadcast to the in-app WebSocket — if nobody has
the dashboard open, a critical alert just sits in the database. For an unattended guard station or
overnight shift, this is a real operational hole, not a nice-to-have.

### Analyst / Dashboards
**Real:** attendance summary, event timeline, and most of the analytics dashboard (department
load, patient-flow buckets) are genuine DB-backed queries (`analytics.py:10-71,161-201`).
**Fake, presented as real:** `system_health.model_status` is a hardcoded literal
(`analytics.py:153-158`, e.g. `"state": "ACTIVE", "progress": 94`), `ai_utilization: 92` is a
magic constant (`:56`), and `security_vault` falls back to three fully fabricated alerts with fake
timestamps when the DB has none (`:227-232`). Anyone looking at this dashboard today is seeing
numbers that were typed in, not measured — this is the kind of thing that destroys credibility
instantly if a real evaluator (the champion you're looking for) notices it.

## 2. Billing — does not exist

Zero hits for "billing"/"invoice"/"payment" anywhere in `backend/`.
`flutter_source/stitch_hospital_billing_dashboard/` contains only a `.DS_Store` file — not even a
UI mockup, an empty directory. If billing is part of the pitch anywhere, it's currently aspirational.

## 3. Small, days-scale fixes (the "small to small pieces" ask)

Roughly ordered by leverage:
1. Fix the five auth holes in §0 (hours each).
2. Delete or wire up `SecurityRule` — either connect it to `rules.py` for real, or remove the CRUD
   UI so it stops looking like a working feature.
3. Replace the three hardcoded/fake analytics values (`analytics.py:56,153-158,227-232`) with real
   computation or an explicit "no data yet" state.
4. Extend the existing webhook alert pattern (already built for one rule type) to the other four
   alert types, or add email/SMS for `severity="critical"` — the plumbing exists, it's just scoped
   too narrowly.
5. Build a minimal equipment-tracking screen in Flutter — the entire backend/API already works,
   only the UI is missing.
6. Wire `Consultation.prescription` to an actual input field/endpoint, or remove it from the API
   response until it's real.
7. Dedupe the near-identical MedGemma report-extraction code between `analysis.py` and
   `patient_portal.py`.
8. Add patient create/delete to `patients.py` (currently read/update only).
9. Delete the duplicate RBAC seed script; write one real `has_permission()` helper and use it
   everywhere instead of string-comparing `.role`.

## 4. Weeks-scale, genuinely new subsystems (not MVP-fast-path)

Appointment scheduling, e-prescribing, lab/HL7-FHIR integration, and any real billing system are
new subsystems, not extensions of what exists. None of these block the camera-compliance pilot
(see `docs/designs/compliance-audit-report-wedge.md`) — they're the next layer once a paying
customer exists to tell you which of these actually matters to them first.
