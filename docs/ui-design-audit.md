# UI/Design Audit — medical_agent

Generated 2026-09-03. Two-part audit: (1) a code-level sweep of the Flutter app
(`flutter_source/lib`) for structural and design-system issues, and (2) a
cross-reference against the actual Stitch design project
(stitch.withgoogle.com/projects/5956398488277013784) once MCP access was set
up — which turned out to be far more complete than "only a few designs": a
full two-theme design system plus 20 designed screens. This second part
changes the diagnosis on several findings below from "AI slop" to "designed
correctly, implemented inconsistently or not at all."

Flutter's CLI isn't installed in this environment, so nothing here is a
pixel-level live render — it's source-code analysis plus direct comparison
against the Stitch screen exports (real screenshots, fetched and viewed).

## 0. The headline finding: there IS a real design system, it's just not centralized

The Stitch project defines two named design systems:

- **"Clinical Clarity"** — light mode, Modern Corporate, medical blues/teals.
  Built for the billing/patient-facing side.
- **"Aetheris Command"** — dark mode, "Premium Glassmorphism" command-center
  aesthetic. Several designed screens are explicitly titled "... - Aetheris
  Mode" (Camera Node Management, Access Node Mapper, Analytics Engine
  Configuration).

**The app's actual colors are the Aetheris Command tokens, verified exact:**
`surface = #041329`, `surface_container = #112036`,
`surface_container_high = #1c2a41`, `surface_container_highest = #27354c`,
`primary_fixed_dim = #38debb` — these are the *literal* hex values already
found hardcoded across 16 Flutter files (`_bgBase`, `_surfaceContainer`,
`_tealAccent`, etc. in `manage_staff_screen.dart`, `security_dashboard.dart`,
`analytics_screen.dart`, and others). This isn't a coincidence — the app was
built from this design system. The "inconsistency" found in the code sweep
(three different teal/cyan values doing the same semantic job) is now
explainable precisely: `#38debb` is `primary_fixed_dim`, `#64ffda` is
`overridePrimaryColor`, `#00d1ff` is `overrideSecondaryColor` — **three
different, individually-correct tokens from the same design system**, applied
ad hoc per screen instead of through one shared theme file. The fix isn't
"invent a palette" — it's "extract the existing, correct tokens into
`ThemeData`/a shared constants file once, and reference them everywhere."

## 1. Designed-but-not-built: the billing dashboard

Confirmed via a real Stitch screenshot ("Hospital Billing Dashboard," mobile,
Clinical Clarity theme): total orders, pending orders, completed, total
revenue metric cards, a searchable recent-orders list with per-row
Edit/Pay/Complete actions, and bottom nav (Dashboard/Patients/Payments). This
is a complete, implementable design — and it corresponds exactly to
`flutter_source/stitch_hospital_billing_dashboard/`, which contains nothing
but a `.DS_Store` file. Combined with the earlier finding that zero
billing/invoice/payment code exists anywhere in `backend/`, this confirms
billing is a fully-designed, zero-percent-built feature — not a vague
future idea, an actual spec sitting unused.

## 2. Designed-but-not-built: Access Node Mapper's real interaction model

The Stitch "Access Node Mapper (RBAC)" screen shows a three-column visual
graph: **Source Nodes** (staff/roles) → **Target Nodes: Clinical Zones**
(camera zones, drawn as connected nodes) → **Permission Levels** (Read/Write/
Update/Lockdown), with visible connector lines between them and a "Deploy
Access Protocol" action plus a red "Emergency Lockdown" button in the sidebar.

This directly explains a finding from the code sweep: `rbac_mapper_screen.dart`
has "Add Entity," "Add Condition," and "Add Zone" buttons that are pure
no-ops (`onPressed: () {}`). They aren't abandoned buttons — they're stubs
for the graph-editing interaction the design calls for (drag-to-connect
source→zone→permission), which is a genuinely harder build than a form, and
was correctly left unstarted rather than half-faked. Two things are still
missing entirely, not just unwired: the connector/graph interaction itself,
and the **Emergency Lockdown** control, which doesn't exist anywhere in the
implemented app (no backend endpoint, no UI) despite being a named,
first-class action in the design.

## 3. Where the fake dashboard numbers actually came from

The Stitch "AI Security Command Center" screen shows a "System Health"
section (donut/percentage cards: 82%, 45%, 75%) and a "Security Vault" table
with sample rows ("Restricted Access Attempt," "Unusual Data Pattern,"
"Credential Verification"). This is not a coincidental resemblance — it's the
direct source of the hardcoded fake values already found in
`backend/routers/analytics.py`: `system_health.model_status` (hardcoded
`"state": "ACTIVE", "progress": 94`), `ai_utilization: 92`, and `security_vault`
falling back to three fabricated alerts with fake timestamps when the DB has
none. **The mockup's placeholder content was carried into the backend
verbatim and never replaced with real computation.** This reframes that
finding: it's not an analyst inventing numbers, it's a design mockup's sample
data that was never swapped out during implementation — a much easier fix
(the real attendance/event data already exists and is already used correctly
elsewhere in the same file) but an urgent one, since anyone who recognizes a
demo mockup's numbers on a "live" dashboard loses trust in the whole product
instantly.

## 4. Structural/navigation findings (code-level sweep)

- **One dead screen:** `patient_portal/patient_details_screen.dart` — fully
  built with real form validation (name required, DOB format check) — is
  never navigated to from anywhere in the app. A patient has no way to view
  or edit their own MRN/DOB/gender. Combined with finding #6 below (patients
  also can't log out), the patient-portal identity/profile experience is
  the least finished part of the app relative to what's actually built.
- **Duplicate, divergent analytics dashboards:** a main-nav
  `analytics/analytics_screen.dart` and a separately-styled
  `settings/analytics_screen.dart` both exist, not sharing implementation.
  Reconcile into one.
- **Nav/permission arrays are hand-duplicated in two files** —
  `lib/main.dart:172-234` and `lib/widgets/shared_app_drawer.dart:23-70` both
  independently list which screens map to which permission string. These
  will silently drift out of sync the next time either list is edited alone.
- **No true role differentiation beyond permission strings** — there's no
  doctor/nurse/security-specific nav; everything is driven by generic
  permission flags from the backend, which is workable but means the "per
  role" experience is only as differentiated as whatever permissions happen
  to be assigned.

## 5. Dead-end buttons (real UI elements, no handler)

Beyond the RBAC mapper (§2), these look actionable but do nothing:
`manage_staff_screen.dart:511` ("View All System Logs"),
`security_dashboard.dart:426` (an alert action button next to a working
"Resolve" button) and `:436` ("View Cam"),
`camera_screen.dart:454` (primary camera tile tap) and `:598` ("Export
Attendance Log"), `settings/analytics_screen.dart:85` ("Diagnostics"),
`login_screen.dart:191-193` ("Request Access"). None of these are marked
disabled or "coming soon" — they're styled identically to working buttons,
so a user (or an evaluator) has no way to tell they don't work except by
clicking them.

## 6. Auth/onboarding and patient-portal UX gaps

- Login screen ships a **"DEV OVERRIDE (DEBUG)" role-chip panel** and an
  **"Enter Patient Portal (Demo)" button hardcoded to `patientId: 1`**
  (`login_screen.dart:197-228`) — the demo button is not gated by
  `kIsWeb`/`kDebugMode` the way the dev chips are. (Functionally this button
  now fails post-fix, since patient_portal's API calls require a real JWT
  the demo path never acquires — but the visible, clickable "Demo" button
  shipping in a production build is still worth removing or properly gating.)
- No "forgot password," no "remember me," and blank-field login submission
  gives **zero feedback** (`login_screen.dart:56-60` silently returns) —
  contrast with wrong-credential failures, which do show a SnackBar.
- Patients have **no logout affordance and no "logged in as" identity
  display** anywhere in `patient_dashboard_screen.dart` — staff get this via
  `shared_app_drawer.dart:199-206`, patients get nothing.
- Staff registration (`manage_staff_screen.dart:807-870`) has no `Form`/
  validator at all beyond a non-empty check — no email/ID format validation.

## 7. Design-system consistency and state coverage (code-level sweep)

- **182 raw hex color literals, 34 distinct values, across 16 files** that
  each define their own local `const Color` block instead of reading from
  one shared theme (see §0 for why this is fixable rather than arbitrary).
- **Loading/empty/error state coverage is uneven:** `security_dashboard.dart`
  has zero loading indicators and wraps its fetches in bare `catch (_) {}` —
  a network failure produces no visible error state at all, just silence.
  `agent_screen.dart` has no top-level loading/error state for initial load
  failures. `manage_staff_screen.dart` and `camera_management_screen.dart`
  are the best-covered screens (multiple spinners, error handlers, and empty
  states each).
- **No responsive breakpoint system** despite targeting web/macOS/Windows/
  Android/iOS — `MediaQuery` appears in 12 files but mostly for ad hoc
  scroll/sizing, alongside hardcoded fixed pixel dimensions
  (`main.dart:372-373` 600×600 splash box, `manage_staff_screen.dart:96-97`
  384×384, `rbac_mapper_screen.dart:592,681,715` 220-280px fixed columns).
  The Stitch design system itself specifies real breakpoints (12-col desktop/
  8-col tablet/4-col mobile grids with defined gutters) — so a responsive
  spec already exists, it just isn't implemented.
- **Accessibility is essentially absent:** zero `Semantics(` widgets and one
  `Tooltip(` in the entire codebase. Worth flagging specifically for a
  hospital-facing product, where accessibility can also be a procurement
  requirement for institutional buyers.

## 7.5. Dark-mode-only enforcement (fixed 2026-09-03)

Per explicit direction: the app is dark mode only, no light theme anywhere.
Swept the whole codebase for light/bright surfaces and found exactly two:

- **`providers/theme_provider.dart`** — a full, unused `lightTheme` (white
  cards, `ColorScheme.light`, black text) plus a `toggleTheme(bool)` method
  that could switch `ThemeMode` to light. Not wired into `main.dart`
  anywhere (verified: zero references to `ThemeProvider`/`toggleTheme`
  outside the file itself), so this was dead code, not a live toggle — but
  it's exactly the kind of unfinished piece that gets wired in later by
  accident. Rewrote the file to be dark-only: removed `lightTheme`,
  `isDarkMode`, and the light branch of `toggleTheme`; `themeMode` is now a
  `const ThemeMode.dark` and `themeData` always returns `darkTheme`.
- **`settings/camera_settings_detail_screen.dart`**'s `AppBar` — the only
  actual bright-surface leak in a live screen: a semi-transparent **white**
  glassmorphic background (`Colors.white.withValues(alpha: 0.6)`) with dark
  slate title text (`Color(0xFF0F172A)`), sitting directly on top of the
  same screen's dark `GlassBackground` body. Fixed to match the rest of the
  app's dark glass headers: background is now the same dark navy
  (`Color(0xFF041329)`) at the same opacity, title text is white, and the
  icon theme moved from `Colors.teal` to `Colors.tealAccent` for better
  contrast against the now-dark bar.

Swept for other candidates and found none: no other `ThemeData.light`/
`ColorScheme.light`/`Brightness.light` usage anywhere, no other
white/light-hex Scaffold, Card, Container, or AppBar backgrounds, and no
light grey (`shade50`/`100`/`200`) surface fills. The app was already
overwhelmingly dark-mode (see §0) — these were the only two exceptions.

## 7.6. Light theme added (reversal of §7.5, 2026-09-03)

Per updated direction, the dark-only restriction from §7.5 was reversed and a
real, working light theme was added instead of removed. Scope of what
"working" means here, stated plainly:

- **`providers/theme_provider.dart`** now defines both themes for real:
  `darkTheme` (unchanged, "Aetheris Command") and `lightTheme` — using the
  actual "Clinical Clarity" token values pulled from the Stitch design
  system (§0), not invented colors. Persists the choice via
  `flutter_secure_storage` (already a dependency, same pattern
  `AuthProvider` uses for the JWT) under key `theme_mode`, defaulting to dark
  when nothing's saved yet.
- **`main.dart`** now registers `ThemeProvider` in the app's `MultiProvider`
  and wires `MaterialApp`'s `theme`/`darkTheme`/`themeMode` to it (previously
  the theme was a single hardcoded inline `ThemeData.dark()` with no toggle
  mechanism at all).
- **`settings/settings_screen.dart`** has a new "Appearance" card with a
  working `Switch` that calls `themeProvider.toggleTheme(...)`.
- **The two shared widgets used by nearly every screen — `GlassBackground`
  and `GlassCard` in `main.dart` — were made theme-aware** (reading
  `Theme.of(context).scaffoldBackgroundColor`/`cardColor`/`colorScheme`
  instead of hardcoded hex). This was the load-bearing fix: without it, the
  toggle would have changed `MaterialApp`'s theme value but produced no
  visible change, since almost every screen wraps its body in one of these
  two widgets.
- **5 additional screens that bypass `GlassBackground` and set their own
  `Scaffold.backgroundColor` directly** (`patient_portal/reports_locker_screen.dart`,
  `upload_report_screen.dart`, `patient_dashboard_screen.dart`,
  `consultations_screen.dart`, and `settings/camera_settings_detail_screen.dart`'s
  `AppBar`) were switched from the hardcoded dark hex to
  `Theme.of(context).scaffoldBackgroundColor` so the whole patient-portal
  flow responds to the toggle too.

**Update (2026-09-03): the remaining gap above is now closed.** All 16 files
identified in §0/§7 (`settings_screen.dart` first, then
`admin/super_admin_dashboard.dart`, `agent/agent_screen.dart`,
`analytics/analytics_screen.dart`, `auth/login_screen.dart`,
`camera/camera_screen.dart`, `consultation/consultation_screen.dart`,
`consultation/report_analysis_view.dart`, `consultation/soap_note_view.dart`,
`patients/patients_list_screen.dart`, `security/security_dashboard.dart`,
`settings/analytics_screen.dart`, `settings/camera_management_screen.dart`,
`settings/live_face_setup_screen.dart`, `settings/manage_staff_screen.dart`,
`settings/rbac_mapper_screen.dart`) had their local `static const Color`/
top-level `const Color` palettes converted to instance getters reading
`Theme.of(context).colorScheme.*`, with every `const` keyword that had baked
in one of those colors at compile time removed (the exact bug class that
produced the washed-out-white-text screenshot on the Settings page). Two
`CustomPainter` classes in `rbac_mapper_screen.dart` (`_BackgroundGridPainter`,
`_EdgePainter`) don't have `BuildContext` access in `paint()`, so their
colors are passed in as constructor parameters from the parent widget's
`build()` instead. Verified with a repo-wide sweep: zero remaining
`static const Color`/top-level `const Color` local palette declarations
anywhere in `lib/`, and brace/paren balance confirmed on every touched file.
Light mode now follows the theme consistently — background, surface, and
foreground/text — across the whole app, not just the background layer.

## 8. Recommended next steps, ordered by leverage

1. **Extract one shared theme file** from the Aetheris Command / Clinical
   Clarity token sets already in the Stitch design system (`designMd` YAML
   front-matter pulled above has every color/typography/spacing value
   pre-named) and migrate the 16 screens off local color consts. This is
   mechanical, not creative — the tokens already exist and are already
   right.
2. **Replace the fake `analytics.py` values** (§3) with real computation —
   the underlying real data (attendance, events) is already queried
   correctly elsewhere in the same file.
3. **Remove or properly gate the login screen's demo/debug UI** (§6).
4. **Decide on billing**: either build the fully-designed dashboard (§1) as
   a real feature, or explicitly deprioritize it and remove the empty
   placeholder folder so it stops looking like in-progress work.
5. **Add loading/error states to `security_dashboard.dart` and
   `agent_screen.dart`** — these are the two screens most likely to be open
   during an actual incident or a live demo, and both currently fail silent.
6. **Wire `patient_details_screen.dart` into patient-portal navigation** and
   add a logout affordance to the patient drawer — small, contained fix for
   a real gap in an otherwise-complete flow.
7. Everything else (dead-end buttons, duplicate analytics screens, nav-array
   duplication, accessibility) is real but lower-urgency polish — worth
   tracking, not worth blocking the compliance-pilot work already in
   progress (see `docs/designs/compliance-audit-report-wedge.md`).
