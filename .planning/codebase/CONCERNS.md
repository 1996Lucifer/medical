---
last_mapped_commit: 27e6902b53907ed07de4b811cef911282bfb9800
last_mapped_at: 2026-09-14
---
# Codebase Concerns

**Analysis Date:** 2026-09-14

> Scope note: this pass covers the full repo (`backend/`, `flutter_source/`). A prior session in
> this same conversation already found and fixed three issues in
> `backend/camera/vision_service_zones.py` (face-recognition threshold, a dead `_identify_person`
> code path, missing temporal confirmation) and `backend/camera/model_manager.py` (unused
> InsightFace submodules) — those are not re-listed as open items below. A separate audit,
> `docs/mvp-gap-audit.md` (2026-09-03), previously found and fixed five live authorization holes
> (unauthenticated `rbac.py`/`patients.py`/`agent.py`/`/uploads`/`security.py:resolve_alert`) — those
> are also not re-listed as open; this document picks up from there and verifies which of that
> audit's still-open items remain, plus new findings from a broader sweep.

## Tech Debt

**Fake/hardcoded analytics data presented as real metrics:**

- Issue: `system_health.model_status` in the dashboard endpoint is a literal hardcoded object —
  `{"name": "Model Llama-X4", "state": "ACTIVE", "progress": 94, "latency_ms": 12}` — which doesn't
  even name a model this system actually runs (the real models are MedGemma/Qwen3, see
  `backend/services/llm_manager.py`). `ai_utilization` is a separate magic constant, and
  `security_vault` fabricates three fake alerts with fake timestamps when the DB has none.
- Files: `backend/routers/analytics.py` (model_status block near line 190, `ai_utilization` near
  line 56, fake alert fallback near lines 227-232)
- Impact: anyone viewing the ops dashboard sees numbers that were typed in, not measured — looks
  like a working AI-ops monitor but isn't. Highest-visibility "fake feature" risk in the product per
  the prior audit.
- Fix approach: replace `model_status` with real state read from `llm_manager` (`active_model_name`,
  a real last-generation latency), compute `ai_utilization` from actual request counts, and return an
  explicit empty state (`[]`) instead of fabricated alerts when there are none.

**`SecurityRule` CRUD exists but is never evaluated:**

- Issue: `routers/security.py` has full CRUD for `SecurityRule` (create/list/replace), with a
  docstring promising "dynamic natural language rules evaluated by Gemini." The actual runtime
  engine, `SecurityRulesEngine` in `backend/rules.py`, never queries this table — every check
  (theft, restricted access, PPE, unauthorized entry, off-hours unknown face) is hardcoded Python.
- Files: `backend/routers/security.py` (SecurityRule endpoints), `backend/models.py:539`
  (`SecurityRule` model), `backend/rules.py` (`SecurityRulesEngine` — no `SecurityRule` query
  anywhere in it)
- Impact: a facility admin can write and save a custom security rule through the Flutter UI today
  and it will silently do nothing — the single most convincing-looking fake feature in the product.
- Fix approach: either wire `SecurityRulesEngine` to load and evaluate rows from `SecurityRule` (the
  originally intended design), or remove the CRUD/UI until that's built.

**Two contradictory RBAC seed scripts still coexist:**

- Issue: `backend/seed_rbac.py` and `backend/seed_hospital_roles.py` each define their own, different
  permission taxonomy and both seed the same `rbac_permissions`/`rbac_groups` tables. Whichever is
  run last silently wins, and there is nothing in the code to warn about the conflict.
- Files: `backend/seed_rbac.py`, `backend/seed_hospital_roles.py`
- Impact: an operator running the "wrong" seed script (or both, in the wrong order) ends up with a
  permission model that doesn't match what the Flutter RBAC UI (`lib/settings/rbac_mapper_screen.dart`)
  or the rest of the backend expects, with no error — just silently wrong grants.
- Fix approach: pick one script, delete the other, and document the canonical one in
  `backend/README`/setup docs.

**Authorization enforcement is a hardcoded superadmin string check, not RBAC-driven:**

- Issue: the only real, consistently-enforced authorization check in the codebase is
  `current_user.role != "superadmin"` (a plain string compare), used in `site_config.py` and
  `routers/auth.py`. The full `RBACGroup`/`RBACPermission` schema and `require_permission()` helper
  exist and are used in a couple of places (`rbac.router`, `tool_executor.py`), but most endpoints
  (e.g. `view_settings`, seeded and shown as "granted" in the Flutter admin UI) are never actually
  checked anywhere.
- Files: `backend/routers/site_config.py:62,90,136`, `backend/routers/auth.py:179`,
  `backend/routers/rbac.py`
- Impact: the permission system looks complete (seeded permissions, group-mapping UI) but is
  decorative for everything except the one superadmin gate — a non-superadmin "Admin" role granted
  `view_settings` today gets no different treatment than one without it.
- Fix approach: replace ad hoc string checks with `require_permission(...)`/`has_permission(...)`
  consistently across every router that currently checks `.role` directly.

**Dead/unwired `Consultation.prescription` field:**

- Issue: `Consultation.prescription` is a real DB column, is exposed in the API response
  (`patient_portal.py`'s response model includes it), but grep confirms zero endpoints ever write to
  it — it was only ever set via a one-off `alter_db.py` migration statement, never a real feature.
- Files: `backend/models.py:152`, `backend/routers/patient_portal.py:43`, `backend/alter_db.py:9`
- Impact: a column that looks like a working "add prescription" feature in the API contract, but
  has no UI or endpoint that populates it — will always be `null` in practice.
- Fix approach: either build a write path (endpoint + Flutter form field), or drop it from the
  response model until it's real.

**Near-duplicate MedGemma report-extraction pipeline (`analysis.py` vs `patient_portal.py`):**

- Issue: the "upload a medical report image/PDF → MedGemma extraction of findings/abnormalities →
  save" pipeline is implemented twice with near-identical logic.
- Files: `backend/routers/analysis.py:21-170`, `backend/routers/patient_portal.py:47-138`
- Impact: any bugfix or prompt/model change to one extraction path has to be manually mirrored in
  the other, or they silently drift apart (already true today — see the "silently swallows JSON
  parse errors" note below, which exists in one copy but not necessarily the other).
- Fix approach: extract the shared extraction logic into a single service function both routers
  call.

**Unpinned Python dependencies:**

- Issue: `backend/requirements.txt` pins nothing — every package (`fastapi`, `torch`-adjacent
  `ultralytics`, `onnxruntime-gpu`, `llama-cpp-python`, `insightface`, `mediapipe`,
  `sentence-transformers`, etc.) is a bare name with no version constraint (a few have `>=` floors
  only: `aiortc`, `av`, `ultralytics`, `openvino`, `psutil`).
- Files: `backend/requirements.txt`
- Impact: `pip install -r requirements.txt` today vs. in 3-6 months can silently pull breaking major
  versions of fast-moving ML libraries (this stack has already been burned by exactly this kind of
  churn — see `Backend_ML_Optimization_Guide.md`); reproducing a known-good environment for a
  redeploy or a new dev machine is not guaranteed.
- Fix approach: pin exact versions (`pip freeze` from a known-working `.venv`) or at minimum
  constrain upper bounds for the ML-heavy packages.

**One-off migration/patch scripts left in the repo:**

- Issue: `backend/alter_db.py`, `backend/backfill_db.py`, `backend/migrate_db.py` are hand-run,
  one-shot ALTER/backfill scripts (predating Alembic, see the `main.py` TODO below) with no
  idempotency guard beyond ad hoc `try/except`, sitting alongside the real Alembic migration
  history in `backend/alembic/versions/`. `patch.py` at the repo root is a throwaway regex-based
  code-injection script that rewrites
  `flutter_source/lib/consultation/consultation_screen.dart` in place — clearly a one-time dev tool,
  now stale and dangerous to run again (it would re-splice generated code into a file that has
  since diverged).
- Files: `backend/alter_db.py`, `backend/backfill_db.py`, `backend/migrate_db.py`, `patch.py`
- Impact: an unfamiliar contributor could reasonably assume these are part of the normal deploy
  flow and re-run one against a live DB or the current Flutter file, corrupting either.
- Fix approach: delete once confirmed applied everywhere (or move into a clearly-labeled
  `scripts/one_off_migrations/` / `scripts/archive/` directory with a comment on when each ran), and
  finish the Alembic migration (see `backend/main.py`'s in-code TODO) so `alter_db.py`/
  `backfill_db.py`/`migrate_db.py` become fully unnecessary.

**Stray debug file at repo root:**

- Issue: `test.dart` (repo root, not under `flutter_source/`) is an 3-line ad hoc scratch file
  (`var p = (data['permissions'] as List).cast<String>();`) unrelated to any test suite or build
  target.
- Files: `test.dart`
- Impact: clutters repo root, has no relationship to `flutter_source/test/`, confusing to a new
  contributor looking for the real test entry point.
- Fix approach: delete.

**Stub services that look production-ready but do nothing:**

- Issue: `VectorRetriever.search()` always returns `[]` — the vector/RAG retrieval path used by
  `services/gateway/query_planner.py`'s `"VECTOR"` strategy is entirely unimplemented (both TODOs
  for embedding the query and running the pgvector similarity search are unaddressed). It still
  eagerly loads a full `SentenceTransformer("all-MiniLM-L6-v2")` model at import time for a method
  that always returns an empty list.
- Files: `backend/services/retrieval/vector_retriever.py`
- Impact: any chat message the intent/tool router falls back to `"VECTOR"` for silently gets zero
  context and the LLM answers with "I don't know" — looks like a working document-retrieval feature
  but is a no-op; also wastes model-load time/memory on every process start for a stub.
- Fix approach: implement the embed + `pgvector` cosine-similarity query (both TODOs already
  describe the exact two steps needed), or remove the `"VECTOR"` strategy from `query_planner.py`
  until it's real.

**Cache invalidation for AI Gateway responses:**

- Issue: `CacheManager` (`services/retrieval/cache_manager.py`) is a plain unbounded in-memory
  `dict` with `get`/`set`/`invalidate` but nothing ever calls `invalidate()` anywhere in the
  codebase, no TTL, and no size cap. `ai_gateway.py` caches every non-image chat response keyed by
  `f"{role}:{message}"`.
- Files: `backend/services/retrieval/cache_manager.py`, `backend/services/gateway/ai_gateway.py`
- Impact: (a) unbounded memory growth over the process lifetime as distinct `role:message`
  combinations accumulate; (b) stale answers — if a cached SQL-backed answer (e.g. "how many
  patients are admitted today") is served again later, it reflects the DB state at cache time, not
  now, with no expiry to force a refresh.
- Fix approach: add a TTL and/or LRU eviction (or swap for the Redis instance already proposed in
  `docs/scaling-architecture.md`), and invalidate on writes to the tables the cached tool queries
  read from.

## Known Bugs

**`SQLRetriever` silently mis-wraps exact-match parameters as `ILIKE` patterns:**

- Symptoms: any string parameter passed into a tool's `sql_template` gets unconditionally wrapped
  as `f"%{v}%"` regardless of whether that template's SQL actually uses `ILIKE` — a template
  written with `WHERE status = :status` would receive `"%active%"` instead of `"active"` and never
  match.
- Files: `backend/services/retrieval/sql_retriever.py` (the `processed_params` loop)
- Trigger: any `agent_config.json` tool whose `sql_template` uses exact-match (`=`) rather than
  `ILIKE` on a string parameter.
- Workaround: none currently — every tool author has to remember to only use `ILIKE`-style matching
  for string params, which isn't documented anywhere near the wrapping logic itself.

**`SQLRetriever` swallows all execution errors as an empty result:**

- Symptoms: any SQL error (bad column name, template referencing a table that changed, a missing
  bind param) is caught by a broad `except Exception` and returns `[]` — indistinguishable from "no
  matching rows."
- Files: `backend/services/retrieval/sql_retriever.py`
- Trigger: any malformed or stale `sql_template` in `agent_config.json` after a schema change.
- Workaround: only visible via the `print(...)` line to stdout — nothing surfaces to the caller,
  metrics, or the user (who just sees "I don't know" from the LLM with no clue a query actually
  failed).

**Patient-portal vitals parsing silently swallows JSON errors:**

- Symptoms: a malformed `MedicalReport.vitals_extracted` JSON blob is silently dropped rather than
  surfaced, so the dashboard vitals chart just shows less data with no "couldn't read this report"
  indicator.
- Files: `backend/routers/patient_portal.py` (around line 169, dashboard vitals aggregation)
- Trigger: any report whose extracted vitals JSON doesn't parse (e.g. a partial/failed MedGemma
  extraction that produced malformed JSON upstream).
- Workaround: none — the failure mode is invisible to both the patient and support staff.

## Security Considerations

**PHI is printed to stdout/logs on every LLM call, despite being encrypted at rest in the DB:**

- Risk: `LLMManager.generate()` and `generate_with_image()` print the full formatted prompt (which
  includes `context_builder`-assembled DB rows — patient names, vitals, consultation notes, etc. via
  `ContextBuilder.build_context`) and the full model response to stdout on every single request,
  unredacted.
- Files: `backend/services/llm_manager.py` (`print(prompt)` / `print(result)` in both `generate()`
  and `generate_with_image()`), `backend/services/llm/context_builder.py` (assembles the PHI-bearing
  context that gets logged)
- Current mitigation: `ConversationHistory.content`/`AgentMemory.fact` are encrypted at rest in the
  DB (`services/security/encryption.py`), but that protection is bypassed entirely by this
  print-to-stdout path — any log aggregation, `nohup` redirect, or terminal scrollback captures
  plaintext PHI regardless of the DB-level encryption.
- Recommendations: gate these prints behind a debug flag (default off) or route through a logger
  with a redaction/truncation policy before this ships anywhere logs are retained, forwarded, or
  shared (support tickets, log aggregators, etc).

**CORS is fully open (`allow_origins=["*"]`) combined with `allow_credentials=True`:**

- Risk: `main.py`'s CORS middleware allows every origin while also allowing credentials — most
  browsers reject this exact combination outright, but the configuration itself signals the CORS
  policy was never actually scoped to the real frontend origin(s); if any browser/proxy is lenient
  about the combination, it's effectively no origin restriction at all for cookie/token-bearing
  requests.
- Files: `backend/main.py` (`CORSMiddleware` registration)
- Current mitigation: none — Authorization uses bearer tokens (not cookies) for the actual API, so
  the practical exposure is lower than a cookie-based scheme, but this is still a wide-open
  configuration for a system holding patient data.
- Recommendations: restrict `allow_origins` to the actual deployed frontend origin(s) (configurable
  per-environment, e.g. via the same env-driven pattern already used in
  `flutter_source/lib/network/environment.dart`).

**Regex-based entity extraction operates directly on chat messages that may contain PHI:**

- Risk: `EntityExtractor.extract_entities()` uses hand-written regexes to pull out "Patient Name,"
  "MRN," "Staff Name," etc. from free-text user messages with no NLP/NER model (the file's own
  docstring flags this as a TODO — GLiNER integration). Regex-based name extraction is fragile
  (fails silently on names with unusual casing/punctuation, or matches the wrong span) and feeds
  directly into which patient's records a SQL tool queries.
- Files: `backend/services/entities/entity_extractor.py`
- Current mitigation: `tool_executor.py`'s RBAC check (`allowed_roles`) limits which roles can run
  which tools at all, but doesn't validate that the *extracted* entity actually refers to a patient
  the requesting user is authorized to see — a nurse asking about "John's report" gets whatever
  patient the regex resolves "John" to, without a per-record authorization check.
- Recommendations: add a per-record authorization check after entity resolution and before running
  the SQL tool (e.g. confirm the resolved patient is one the caller's role/assignment permits),
  independent of improving the extraction accuracy itself.

## Performance Bottlenecks

**Global lock serializes all LLM generation across the whole backend:**

- Problem: `LLMManager` uses a single `threading.Lock()` (`_model_lock`) around both model-loading
  and the actual `model(...)` inference call. Only one LLM generation (chat or vision) can run at a
  time across the entire process, and switching between MedGemma and Qwen3 mid-stream (which
  happens whenever intent alternates between clinical/non-clinical) triggers a full model
  unload+reload from disk inside that same lock.
- Files: `backend/services/llm_manager.py` (`_model_lock`, `_load_specific_model`)
- Cause: `_load_specific_model` explicitly unloads the other model to control memory, and both
  `generate()`/`generate_with_image()` hold `_model_lock` for the entire load-then-infer sequence.
- Improvement path: acceptable for a single-user/kiosk-style deployment; will not scale to
  concurrent multi-user chat without either running both models resident simultaneously (if memory
  allows) or moving to a proper model-serving layer (vLLM is already selected for the Nvidia-GPU
  path in `_select_engine()`, which supports concurrent requests natively — the CPU/Apple-Silicon
  paths via `llama-cpp-python` don't).

**Per-request background thread for memory extraction, no pooling:**

- Problem: every chat turn spawns a brand-new `threading.Thread` (daemon, no pool, no limit) to run
  `memory_extractor.extract_and_save_background`, which itself makes another full LLM `generate()`
  call (contending for the same `_model_lock` above) plus a DB write.
- Files: `backend/services/gateway/workflow_engine.py` (`execute_workflow`, step 8)
- Cause: no `ThreadPoolExecutor`/queue — thread count scales linearly with concurrent chat volume.
- Improvement path: route through a bounded worker pool (the codebase already uses
  `ThreadPoolExecutor` elsewhere, e.g. `backend/camera/worker.py`'s `_io_pool`), or make this a
  proper background job queue once request volume grows.

**Single-machine camera inference architecture cannot scale to multi-building deployments:**

- Problem: `camera/vision_worker.py`'s `VisionProcessManager` pools inference across
  `multiprocessing.Process` subprocesses using `multiprocessing.shared_memory` for frame IPC —
  shared memory only works between processes on the same host.
- Files: `backend/camera/vision_worker.py` (lines ~46-47, ~124, ~160-315 per
  `docs/scaling-architecture.md`)
- Cause: architecture assumes one server per hospital; there's no way today to point a worker at a
  GPU box in a different building without replacing the IPC layer.
- Improvement path: already designed (not yet implemented) — see `docs/scaling-architecture.md`'s
  proposal to replace shared-memory IPC with Redis Streams so inference workers can run on
  additional machines with consumer-group load balancing.

## Fragile Areas

**`backend/camera/worker.py` (1,350 lines) — largest file in the backend:**

- Files: `backend/camera/worker.py`
- Why fragile: mixes RTSP frame-reading threads, a module-level `active_workers: Dict[str,
  CameraWorker]` global registry, per-camera locks, a shared `ThreadPoolExecutor` for I/O, and ROI
  fetch state — a lot of concurrent, stateful machinery in one file with no test coverage (see Test
  Coverage Gaps below).
- Safe modification: changes touching threading/lifecycle here need manual, live-camera testing —
  there's no automated harness that exercises `CameraWorker` start/stop/reconnect behavior.
- Test coverage: none — zero test files reference `camera/worker.py`.

**Print-based logging throughout the backend (39 files use `print()`, 1 uses `logging`):**

- Files: `backend/services/calls/authorization.py` (or similar) is essentially the only real user of
  Python's `logging` module; everywhere else (`main.py`, `llm_manager.py`, `sql_retriever.py`,
  `tool_executor.py`, camera modules, etc.) use bare `print()` for both informational and error
  output.
- Why fragile: no log levels, no structured fields, no easy way to filter/ship logs to an
  aggregator, and (per the PHI-in-stdout finding above) no centralized place to add
  redaction — every `print()` call site would need an individual fix.
- Safe modification: introduce a shared `logging` config once, then migrate call sites incrementally
  (highest priority: `llm_manager.py`'s prompt/response prints).

**Bare/broad exception handling hides real failures in several hot paths:**

- Files: `backend/correlation_engine.py:36`, `backend/routers/patient_portal.py:190`,
  `backend/routers/staff.py:689`, `backend/camera/audio_service.py:134,173` (bare `except:`); 35
  occurrences of `except Exception:` with no logging/handling beyond `pass` or a bare `print(...)`
  across the backend.
- Why fragile: a bare `except:` also catches `KeyboardInterrupt`/`SystemExit` and masks programming
  errors (typos, wrong attribute names) as if they were expected runtime conditions — makes real
  bugs indistinguishable from expected edge cases during debugging.
- Safe modification: narrow each to the specific exception type actually expected at that call
  site, and log unexpected ones instead of silently swallowing.

## Scaling Limits

**In-process, single-worker deployment assumption throughout auth/caching/camera:**

- Current capacity: login rate-limiting (`routers/auth.py`'s `_login_failures_lock`/in-memory dict),
  `CacheManager`, and camera worker pooling are all per-process, in-memory state.
- Limit: none of this is shared across processes — running `uvicorn --workers N` (or multiple
  replicas behind a load balancer) would give each worker its own independent login-attempt counter
  and response cache, silently weakening both (an attacker could get `N`x the login attempts by
  landing on different workers).
- Scaling path: move shared state to Redis (already proposed for the camera-scaling piece in
  `docs/scaling-architecture.md` — the same instance could back rate-limiting and caching too)
  before running more than one backend process.

## Dependencies at Risk

**Unpinned, fast-moving ML dependency stack:**

- Risk: `ultralytics`, `onnxruntime-gpu`, `insightface`, `mediapipe`, `sentence-transformers`,
  `llama-cpp-python`, and `openvino` are all unpinned (see Tech Debt above) and are among the
  fastest-breaking-change packages in the Python ML ecosystem.
- Impact: a fresh `pip install` months from now can pull incompatible versions (API renames, ONNX
  opset mismatches, GGUF format changes) with no warning until runtime.
- Migration plan: pin to the exact versions verified working today (`pip freeze` from the current
  working `.venv`), then upgrade deliberately and test rather than floating.

## Test Coverage Gaps

**Backend has one test file for the entire application:**

- What's not tested: `backend/test_indoor_tracking.py` (207 lines) is the only test file in
  `backend/` — nothing exercises `main.py`'s auth/CORS/static-file gating, any router
  (`patients.py`, `agent.py`, `security.py`, `rbac.py`, `analytics.py`, etc.), `rules.py`'s
  `SecurityRulesEngine`, `llm_manager.py`, or any of the `services/` modules (gateway, routing,
  tools, memory, retrieval).
- Files: only `backend/test_indoor_tracking.py` exists; no `tests/` directory, no `pytest.ini`/
  `conftest.py` beyond the default.
- Risk: the auth fixes documented in `docs/mvp-gap-audit.md` (previously-open unauthenticated
  routers) have no regression test guarding against a future change accidentally re-removing
  `auth_dep` from a router in `main.py` — that class of bug could silently reappear.
- Priority: High — at minimum, an auth/RBAC regression suite covering "every router requires a
  valid token" and "role X cannot call permission-gated endpoint Y" would directly protect the fixes
  already made once.

**Flutter has one real widget test:**

- What's not tested: `flutter_source/test/widget_test.dart` is a single smoke test confirming the
  app builds and shows the login screen. No widget/unit tests exist for any of the ~40+ screens
  under `lib/` (settings, admin, camera, patient_portal, security, indoor_tracking, etc.), and no
  provider (`AuthProvider`, `SiteConfigProvider`, etc.) has a unit test.
- Files: `flutter_source/test/widget_test.dart` (only test file); `flutter_source/test_uri.dart`
  was checked for and does not exist in the current tree.
- Risk: the largest screens (`settings/manage_staff_screen.dart` at 1,769 lines,
  `settings/rbac_mapper_screen.dart` at 1,429 lines, `consultation/consultation_screen.dart` at
  1,301 lines) have no automated coverage at all despite being among the most complex/stateful
  parts of the app.
- Priority: Medium — given the app is still evolving quickly, prioritize provider-level unit tests
  (auth/session logic) over full widget trees first.

**No tests for the AI gateway pipeline (`intent → entity → tool/vector → LLM`):**

- What's not tested: `services/gateway/workflow_engine.py`'s full pipeline (intent routing, entity
  extraction, query planning, tool execution/RBAC denial, memory retrieval/injection, LLM
  generation) has zero test coverage. This is the code path that decides which SQL a user's free
  text message triggers and which role can see the result.
- Files: `backend/services/gateway/workflow_engine.py`, `backend/services/routing/intent_router.py`,
  `backend/services/entities/entity_extractor.py`, `backend/services/tools/tool_executor.py`
- Risk: silent regressions in intent keyword matching (`agent_config.json`-driven) or RBAC
  enforcement in `tool_executor.py` would ship undetected — this is also the component most
  recently patched for a real access-control gap (allowed_roles enforcement, per the code comment
  in `tool_executor.py`).
- Priority: High — this is the component with the most recent history of exactly this class of bug
  (declared-but-unenforced RBAC).

---

*Concerns audit: 2026-09-14*
