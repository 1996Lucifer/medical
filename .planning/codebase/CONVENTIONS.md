---
last_mapped_commit: 27e6902b53907ed07de4b811cef911282bfb9800
last_mapped_at: 2026-09-14
---
# Coding Conventions

**Analysis Date:** 2026-09-14

This project has two codebases with distinct conventions: the Python/FastAPI backend (`backend/`) and the Flutter/Dart frontend (`flutter_source/`). Neither has an enforced formatter/linter config for the backend (no `pyproject.toml`, `.flake8`, or `ruff.toml` found); the frontend uses the stock `flutter_lints` package (`flutter_source/analysis_options.yaml`).

## Naming Patterns

**Backend files (`backend/`):**

- Module-per-domain, `snake_case.py`: `routers/patients.py`, `routers/staff.py`, `services/llm_manager.py`, `services/gateway/ai_gateway.py`.
- Sub-packages group related services: `services/entities/`, `services/gateway/`, `services/memory/`, `services/retrieval/`, `services/routing/`, `services/security/`, `services/tools/`, `services/calls/`, `services/metrics/`.
- Pure, DB-free logic modules live directly under their domain package, e.g. `indoor_tracking/fusion.py`, `indoor_tracking/gating.py` — see docstring in `backend/indoor_tracking/fusion.py`: "Every function here is pure / DB-free so it's directly unit-testable."

**Backend functions/variables:**

- `snake_case` throughout, e.g. `get_current_user`, `create_access_token`, `_assert_patient_access` (`backend/routers/patients.py`).
- Private/internal helpers are prefixed with a single underscore: `_assert_patient_access`, `_is_locked_out`, `_record_login_failure`, `_clear_login_failures` (`backend/routers/auth.py`), `_create_login_for_staff`, `_log_activity`, `_time_to_hhmm` (`backend/routers/staff.py`).
- Module-level constants are `UPPER_SNAKE_CASE`: `SECRET_KEY`, `ALGORITHM`, `ACCESS_TOKEN_EXPIRE_MINUTES` (`backend/routers/auth.py`), `CAMERA_SEEN_DECAY_SEC`, `GPS_MAX_CONFIDENCE` (`backend/indoor_tracking/fusion.py`).

**Backend classes:**

- Pydantic request/response models are named `<Entity><Purpose>` and suffixed `Request`/`Response`: `PatientResponse`, `PatientUpdateRequest`, `CreateLoginResponse`, `DoctorContact` (`backend/routers/patients.py`), `StaffResponse`, `StaffUpdate`, `CreateStaffLoginResponse` (`backend/routers/staff.py`).
- SQLAlchemy ORM models use singular `PascalCase`: `User`, `Patient`, `RBACGroup`, `RBACPermission` (`backend/models.py`).
- Service singletons/orchestrators use `PascalCase` classes with a lowercase module-level instance exported alongside: `class AIGateway` (`backend/services/gateway/ai_gateway.py`), `llm_manager` (`backend/services/llm_manager.py`), `cache_manager` (`backend/services/retrieval/cache_manager.py`), `metrics_tracker` (`backend/services/metrics/metrics.py`).

**Frontend files (`flutter_source/lib/`):**

- Feature-first folders per domain, not by type: `auth/`, `call/`, `camera/`, `indoor_tracking/`, `patient_portal/`, `settings/`, `security/`, `directory/`, `consultation/`, `analytics/`, `admin/`, `profile/`, `agent/`.
- Cross-cutting infra lives in dedicated top-level folders: `network/` (HTTP layer), `providers/` (app state), `storage/` (secure storage), `widgets/` (shared widgets), `utils/` (platform shims).
- File naming is `snake_case.dart` with a role suffix: `*_screen.dart` for full pages (`patient_dashboard_screen.dart`, `settings_screen.dart`), `*_service.dart` for network/business logic (`call_service.dart`, `rfid_service.dart`, `tracking_signal_service.dart`), `*_provider.dart` for `ChangeNotifier` state (`auth_provider.dart`, `site_config_provider.dart`, `theme_provider.dart`), `*_models.dart` for plain data/enum classes (`call_models.dart`).

**Frontend classes/members:**

- `PascalCase` for classes/enums: `AuthProvider`, `NetworkManager`, `CallPeer`, `CallMode`, `CallState`.
- `camelCase` for methods/variables/getters.
- Private state fields prefixed `_` with a public getter of the same name minus the underscore — see `backend`-adjacent pattern mirrored in Dart: `bool _isAuthenticated; bool get isAuthenticated => _isAuthenticated;` (`flutter_source/lib/providers/auth_provider.dart:15,34`).

## Code Style

**Backend formatting:**

- No enforced formatter; style is consistent by convention rather than tooling. Follow existing file conventions rather than introducing a new style (e.g. Black) unannounced.
- Double-quoted strings are the norm (`main.py` uses `"` roughly 5x more often than `'`); use double quotes for new backend string literals unless embedding a double quote.
- Imports are grouped stdlib → third-party → local, generally alphabetized within each SQLAlchemy `import (...)` block (`backend/models.py:6-16`) and within FastAPI route files (`backend/routers/patients.py:1-10`).
- Comment blocks explaining *why* (not *what*) precede non-obvious code, often multi-line prose above the affected block — see the CORS/middleware-ordering rationale (`backend/main.py:170-172`), the SECRET_KEY fail-loudly rationale (`backend/routers/auth.py:17-25`), and the login-rate-limiting rationale (`backend/routers/auth.py:47-58`). Follow this pattern for any security-sensitive or non-obvious logic: explain the "why", not the mechanics.

**Frontend formatting:**

- Standard `dart format` defaults (2-space indent, trailing commas on multi-line arg lists).
- Single or double quotes both appear; prefer single quotes for simple string literals (majority pattern in `auth_provider.dart`, `network_manager.dart`) and double quotes when the string contains an apostrophe or for template-like log messages.
- `flutter_lints: ^3.0.0` is active (`flutter_source/analysis_options.yaml`) — no rules are currently customized beyond the default set; do not disable lints without discussion.

## Import Organization

**Backend (`backend/*.py`):**

1. Standard library (`os`, `re`, `shutil`, `datetime`, `threading`, `time`)
2. Third-party (`fastapi`, `sqlalchemy`, `pydantic`, `jwt`, `bcrypt`, `dotenv`)
3. Local modules, unqualified (`models`, `from database import get_db`, `from routers.auth import ...`, `from services.llm_manager import llm_manager`)

No path aliasing — backend imports are always relative to `backend/` as the root package (run from `backend/` as cwd; `main.py` imports `models`, `database`, `routers.*`, `services.*` directly).

**Frontend (`flutter_source/lib/**/*.dart`):**

1. `dart:` core libraries (`dart:convert`, `dart:developer`)
2. `package:` third-party (`package:flutter/material.dart`, `package:flutter_secure_storage/...`)
3. Relative local imports last, using `../` (`../network/api_routes.dart`, `../network/network_manager.dart`, `../indoor_tracking/tracking_signal_service.dart`) — see `flutter_source/lib/providers/auth_provider.dart:1-9`.

No `package:frontend/...` absolute imports used within `lib/` for intra-package references; relative imports are the norm there. The one absolute `package:frontend/...` import style appears only from `flutter_source/test/widget_test.dart` (test code importing the app package by name is required by Flutter's test tooling).

## Error Handling

**Backend:**

- FastAPI routes raise `HTTPException(status_code=..., detail="...")` directly at the point of failure — the dominant pattern (114+ call sites). Always include a human-readable `detail` string; e.g. `HTTPException(status_code=404, detail="Patient not found")`, `HTTPException(status_code=403, detail="You do not have access to this resource.")` (`backend/routers/patients.py`).
- Access-control checks are factored into small `_assert_*`/`require_permission(...)` helpers reused across endpoints rather than inlined per-route (`backend/routers/patients.py:15-25`, `backend/routers/auth.py`'s `require_permission`).
- Background/best-effort operations (startup hooks, embedding loads, cleanup) use broad `except Exception as e: print(...)` so a failure there never crashes the app — see `backend/main.py`'s `lifespan()` (RFID station provisioning, embeddings background load) and the vector-extension bootstrap at `backend/main.py:36-40`. Reserve this broad-catch-and-log pattern for genuinely non-critical background paths, not for request-handling logic where a `4xx`/`5xx` should propagate.
- One custom exception class exists: `ToolAccessDenied` (`backend/services/tools/tool_executor.py`) for RBAC failures inside the agent tool-execution path, caught and translated by its caller rather than bubbling as a raw 500.
- Security-relevant failure modes are documented inline with the *incident/rationale* that led to the fix, not just the fix itself (see `backend/routers/auth.py`'s SECRET_KEY and rate-limiting comments). Follow this precedent: when hardening a security path, leave a comment explaining the prior vulnerability and why the new behavior is required.

**Frontend:**

- Network calls wrap `NetworkManager.instance.<verb>(...)` in `try { ... } catch (e) { ... }`, decode JSON defensively, and surface a user-facing `_error` string on the relevant provider rather than throwing up the widget tree — see `AuthProvider.login()`, `AuthProvider.changePassword()` (`flutter_source/lib/providers/auth_provider.dart`).
- Non-2xx HTTP responses are handled by checking `response.statusCode` explicitly (no exceptions thrown by `NetworkManager` itself); the caller decides how to interpret each status code.
- Storage failures (secure storage read/write) are caught and logged via `debugPrint(...)` without failing the calling flow — auto-login degrades gracefully to "not authenticated" rather than crashing (`flutter_source/lib/providers/auth_provider.dart:66-70,96-107`).
- Use `debugPrint`/`log` (from `dart:developer`) for diagnostic output in the frontend, not `print`.

## Logging

**Backend:**

- `print(...)` is the dominant logging mechanism (found in ~39 backend files) — e.g. `print(f"[AIGateway] Cache HIT for message: {message}")` (`backend/services/gateway/ai_gateway.py`), `print(f"Failed to load embeddings on startup: {e}")` (`backend/main.py`). Only 2 files use the `logging` module. When adding new backend code, match the existing `print(...)` convention rather than introducing `logging` in isolation (a wholesale migration is a larger, separate decision).
- Prefix log messages with a bracketed component tag where useful for grep-ability, e.g. `"[AIGateway] ..."`, `"[auth] WARNING: ..."`.

**Frontend:**

- Use `debugPrint("<Context>: $e")` for recoverable/expected errors and `log("$e")` (from `dart:developer`) for unexpected ones — both patterns coexist in `AuthProvider` (`flutter_source/lib/providers/auth_provider.dart:69,102,131,191`).

## Comments

- Both codebases favor **prose comment blocks explaining rationale** over line-by-line "what" comments — especially around security decisions, ordering-sensitive middleware, and non-obvious business rules. Examples: the CORS/middleware ordering note and RFID dual-auth note in `backend/main.py:169-172,225-229`; the patient-record access-control docstring in `backend/routers/patients.py:16-21`; the `_maybeStartTracking` docstring in `flutter_source/lib/providers/auth_provider.dart:135-136`.
- Docstrings (`"""..."""`) are used on modules and non-trivial functions in the backend to state purpose, invariants, and callers — see the module docstring in `backend/indoor_tracking/fusion.py:1-19`.
- Dart doc comments (`///`) are used sparingly on public methods that need usage context, e.g. `flutter_source/lib/providers/auth_provider.dart:58-59,28-32`.
- TODOs are written as `TODO(<area>): <explanation>` with enough context to act on later without re-deriving the reasoning — see `backend/main.py:42-48` (`TODO(migrations): ...`).

## Function Design

**Backend:**

- Route handler functions do request validation → permission/ownership check → DB query → mutation → response-model construction, in that order (see every handler in `backend/routers/patients.py`). Keep new endpoints in this order for consistency.
- Pure computational logic is deliberately separated from FastAPI/DB-touching code into standalone modules with no framework dependency, specifically to make it unit-testable without spinning up the app or a database — the explicit intent stated in `backend/indoor_tracking/fusion.py`'s module docstring. Prefer this separation (`compute` module + thin router/service wrapper) for new business logic with any non-trivial branching.
- Response Pydantic models are constructed with all fields passed by keyword at the call site, not via `.from_orm`/`model_validate` shortcuts, even though `model_config = ConfigDict(from_attributes=True)` is declared — e.g. `PatientResponse(id=p.id, name=p.name, ...)` (`backend/routers/patients.py:52-56`). Both patterns exist in the codebase; keyword construction is more common in router files.

**Frontend:**

- Provider methods (`AuthProvider.login`, `.changePassword`, `.tryAutoLogin`) follow the shape: set loading/error state → `notifyListeners()` → await network call → branch on `statusCode` → update state → `notifyListeners()` → return a `bool`/void result. Match this shape for new provider methods.
- Widgets are not deeply decomposed by default — screens (`*_screen.dart`) tend to hold most of their own layout logic rather than being split into many small private widget classes; shared cross-screen widgets go in `flutter_source/lib/widgets/`.

## Module Design

**Backend:**

- Each `routers/*.py` module owns one `APIRouter()` with a fixed `prefix="/api/<domain>"` and `tags=[...]`, registered in `backend/main.py` with per-router `dependencies=` for auth (see the router-registration block, `backend/main.py:186-229`). New domains should follow this one-router-per-file-with-prefix pattern.
- `services/` holds framework-agnostic business logic organized by concern (`gateway`, `routing`, `retrieval`, `memory`, `tools`, `security`, `metrics`, `calls`, `entities`) rather than by feature — routers call into `services/*` rather than embedding orchestration logic inline.
- Long-lived singletons are instantiated once at module import time and exported by name in lowercase (`llm_manager`, `cache_manager`, `metrics_tracker`) rather than passed around via dependency injection.

**Frontend:**

- State is managed via `provider`/`ChangeNotifier` (`providers/*.dart`), injected at the app root (`MultiProvider` in `main.dart`/`test/widget_test.dart`) and consumed with `Provider.of`/`Consumer` in screens — no other state management library is used (no Riverpod, Bloc, GetX).
- `NetworkManager` is a singleton (`NetworkManager.instance`) that owns the JWT token and wraps `package:http` for all HTTP calls; screens/services never call `package:http` directly, they go through `NetworkManager` (`flutter_source/lib/network/network_manager.dart`).
- API endpoint URLs are centralized in `flutter_source/lib/network/api_routes.dart` (referenced as `ApiRoutes.authMe`, `ApiRoutes.login`, etc.) rather than hardcoded per call site — follow this for any new endpoint.

---

*Convention analysis: 2026-09-14*
