---
last_mapped_commit: 27e6902b53907ed07de4b811cef911282bfb9800
last_mapped_at: 2026-09-14
---
# Testing Patterns

**Analysis Date:** 2026-09-14

**Overall state: minimal.** There is no repo-wide test suite. Exactly one real automated test file exists on the backend (`backend/test_indoor_tracking.py`, 23 pure-function unit tests) and exactly one on the frontend (`flutter_source/test/widget_test.dart`, a single smoke test). This is confirmed by project docs: `docs/designs/compliance-audit-report-wedge.md:312` states "No test framework exists repo-wide; new subsystem gets scoped pytest coverage." Treat any new test work as establishing precedent, not following an existing broad convention — but do follow the two patterns below where they apply.

## Test Framework

**Backend runner:**

- `pytest` 9.1.1, installed in `backend/.venv` (`backend/.venv/lib/python3.14/site-packages/pytest-9.1.1.dist-info`) but **not declared in `backend/requirements.txt`** — install manually (`pip install pytest`) before running tests locally or in CI.
- No `pytest.ini`, `pyproject.toml`, or `conftest.py` exists anywhere in the backend — no shared fixtures, no custom markers, no coverage config.
- No test-runner npm/make script; run directly with `pytest` from `backend/`.

**Frontend runner:**

- `flutter_test` (bundled with Flutter SDK) declared in `flutter_source/pubspec.yaml` under `dev_dependencies`.
- `flutter_lints: ^3.0.0` is the only other dev dependency — no `mockito`, `mocktail`, `bloc_test`, or `integration_test` package is present.

**Run commands:**

```bash

# Backend (from backend/, with backend/.venv activated)

./.venv/bin/pytest test_indoor_tracking.py -v
./.venv/bin/pytest test_indoor_tracking.py -k test_gating   # filter by name

# Frontend (from flutter_source/)

flutter test                      # runs test/widget_test.dart
flutter test test/widget_test.dart -v
```

There is no coverage tooling configured for either side (no `pytest-cov`, no `flutter test --coverage` usage found in scripts).

## Test File Organization

**Backend:**

- The single existing test file sits at the backend root, not in a `tests/` directory: `backend/test_indoor_tracking.py`. It targets the `indoor_tracking` package (`backend/indoor_tracking/fusion.py`, `backend/indoor_tracking/gating.py`) directly by import: `from indoor_tracking import fusion, gating`.
- Naming: `test_<module>.py` at the file level, `test_<behavior_description>()` at the function level — descriptive, full-sentence-style names rather than `test_1`/`test_ok`, e.g. `test_gating_paused_when_outside_geofence_during_working_hours`, `test_fuse_disagreeing_candidates_trusts_strongest_and_lowers_confidence`.
- Tests are grouped by source module using a comment banner divider, not classes:
  ```python
  # ── fusion.py ────────────────────────────────────────────────────────────
  def test_camera_seen_candidate_decays_over_time(): ...

  # ── gating.py ────────────────────────────────────────────────────────────
  def test_gating_stopped_when_session_closed(): ...
  ```
  Follow this banner-comment grouping convention when adding tests that cover multiple modules in one file.
- If/when a `tests/` directory is introduced for a new subsystem, mirror the source package layout (e.g. `backend/tests/test_<module>.py` per `backend/<package>/<module>.py`) since no existing convention contradicts this and it matches the single existing file's one-test-file-per-source-module pattern.

**Frontend:**

- `flutter_source/test/widget_test.dart` is the only file, at the root of `test/`. If more widget/unit tests are added, mirror `lib/`'s feature-first structure under `test/` (e.g. `test/auth/auth_provider_test.dart` for `lib/providers/auth_provider.dart`) — there is no existing counter-example to follow instead.

## Test Structure

**Backend — flat `pytest` functions, no classes, no fixtures:**

```python
import datetime
from indoor_tracking import fusion, gating

def test_wifi_candidate_multi_ap_trilateration_between_aps():
    known_aps = [
        {"bssid": "AA:1", "x": 0, "y": 0, "floor_id": 1, "coverage_radius_m": 8},
        {"bssid": "AA:2", "x": 10, "y": 0, "floor_id": 1, "coverage_radius_m": 8},
    ]
    readings = [{"bssid": "AA:1", "rssi": -50}, {"bssid": "AA:2", "rssi": -50}]
    c = fusion.wifi_candidate(known_aps=known_aps, readings=readings)
    assert c.source == "wifi_trilateration"
    assert 0 < c.x < 10  # equal signal -> roughly midway
    assert abs(c.y) < 1e-6
```

- Arrange inputs as plain dicts/dataclasses inline in the test body (no factory functions or fixture files).
- One behavior per test; assertions include an inline comment explaining *why* the expected value is correct when it's not obvious (`# equal signal -> roughly midway`, `# 0.4*10 + 0.6*0`).
- Shared constants used across related tests are defined once near the tests that use them, e.g. `HOSPITAL_SQUARE = [(0, 0), (0, 1), (1, 1), (1, 0)]` above the `gating` test group (`backend/test_indoor_tracking.py:127`).
- No `setUp`/`tearDown`, no `pytest.fixture` — every test is fully self-contained since the code under test is pure (no DB/app context), per the module docstring's stated design goal.

**Frontend — `flutter_test`'s `testWidgets`:**

```dart
void main() {
  testWidgets('App builds and shows the login screen', (tester) async {
    final authProvider = AuthProvider();
    final router = buildAppRouter(authProvider);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: authProvider),
          ChangeNotifierProvider(create: (_) => SiteConfigProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: MyApp(router: router),
      ),
    );
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
```

- Test descriptions are full sentences describing observable behavior (`'App builds and shows the login screen'`).
- Real (non-mocked) provider instances are constructed directly and wired through the same `MultiProvider` shape the real `main.dart` uses — no test-double/mocking layer exists yet for providers or `NetworkManager`.
- A code comment documents *why* the test looks the way it does (it replaced Flutter's default counter-app template test, which asserted behavior this app never had) — follow this precedent of leaving a short "why this test looks like this" note when replacing boilerplate.

## Mocking

**Backend:** No mocking library is used or present (no `unittest.mock`, no `pytest-mock`). This is enabled by the codebase's own convention of keeping business logic pure/DB-free specifically so it doesn't need mocking (`backend/indoor_tracking/fusion.py`'s docstring: "Every function here is pure / DB-free so it's directly unit-testable"). When adding tests for DB-touching code (routers, services that call `db.query(...)`), either:

1. Extract the pure decision logic into a separate DB-free module (preferred, matches existing precedent), or
2. Introduce `pytest`'s dependency-override mechanism via FastAPI's `app.dependency_overrides[get_db]` (not yet used anywhere in this codebase, so there is no existing pattern to copy — establish one deliberately rather than guessing at conventions that don't exist).

**Frontend:** No mocking library (`mockito`/`mocktail`) is installed. The one existing test uses real provider instances rather than fakes. For screens that depend on `NetworkManager`/HTTP calls, there is currently no seam for injecting a fake — `NetworkManager` is a hard singleton (`NetworkManager.instance`), so testing network-dependent widgets would require either adding an injectable HTTP client or accepting an integration-style test against a running backend.

## Fixtures and Factories

Neither codebase has a fixtures/factories layer:

- Backend: no `conftest.py`, no factory library (e.g. `factory_boy`), test data is constructed inline as dicts/dataclasses per test.
- Frontend: no golden files, no test data builders; the one widget test constructs real `AuthProvider()`/`SiteConfigProvider()`/`ThemeProvider()` instances directly.

## Coverage

No coverage tooling or targets are configured on either side. No `.coveragerc`, no `pytest-cov` in the environment, no `flutter test --coverage` usage in any script (`backend/start.sh`, `manage.sh`, `start_services.sh` all only start services, none run tests).

## Test Types

**Unit tests:** The only test type present. Backend: 23 pure-function tests over `indoor_tracking/fusion.py` and `indoor_tracking/gating.py`. Frontend: 1 widget smoke test over app boot.

**Integration tests:** None. No FastAPI `TestClient`/`httpx.AsyncClient` usage anywhere in the backend, no test hitting a real or in-memory DB.

**E2E tests:** None. No Flutter `integration_test` package, no Playwright/Cypress config for any web surface.

## Common Patterns

**Backend — decaying/time-based assertions:**

```python
def test_camera_seen_candidate_decays_over_time():
    fresh = fusion.camera_seen_candidate(camera_x=1, camera_y=2, floor_id=1, coverage_radius_m=5, seconds_since_seen=0)
    stale = fusion.camera_seen_candidate(camera_x=1, camera_y=2, floor_id=1, coverage_radius_m=5, seconds_since_seen=55)
    expired = fusion.camera_seen_candidate(camera_x=1, camera_y=2, floor_id=1, coverage_radius_m=5, seconds_since_seen=120)
    assert fresh.confidence > stale.confidence
    assert expired is None
```

Prefer relative assertions (`fresh.confidence > stale.confidence`) over hardcoded magic numbers when testing decay/scoring functions, reserving exact-value assertions for simple deterministic math (e.g. `test_smooth_moves_toward_new_point_gradually` asserts `x == 4.0  # 0.4*10 + 0.6*0`).

**Backend — "none/empty" edge cases get their own test:**
Every fusion/gating function that can return `None` has a dedicated test for that path, e.g. `test_gps_candidate_none_without_floor_calibration`, `test_wifi_candidate_unknown_bssid_returns_none`, `test_fuse_empty_returns_none`. Follow this when adding new pure functions with optional/None return paths.

**Frontend — async widget pump pattern:**

```dart
await tester.pumpWidget(/* ... */);
await tester.pump();
expect(find.byType(MaterialApp), findsOneWidget);
```

Single `pump()` after `pumpWidget()` is sufficient for the current smoke test since it only asserts the app boots; tests exercising async state changes (network calls, animations) will need `pumpAndSettle()` instead — no existing example to copy, so establish this deliberately per new test's needs.

## Recommendations for New Test Coverage

- For new backend business logic: follow the `indoor_tracking` precedent — write pure, DB-free functions and test them directly with plain `pytest` functions, no fixtures needed.
- For new backend route/DB-touching logic: no existing pattern covers this gap. Introduce FastAPI's `TestClient` + `app.dependency_overrides` deliberately if/when this is needed, and add `pytest` (and ideally `httpx`) to `backend/requirements.txt` at that point since `pytest` currently only exists by way of a manually-installed venv package.
- For new frontend logic: provider-level unit tests (constructing a provider directly and asserting on its getters after calling a method) would fit the existing pattern better than widget tests, since `AuthProvider` in the one existing test is already constructed directly with no mocking.

---

*Testing analysis: 2026-09-14*
