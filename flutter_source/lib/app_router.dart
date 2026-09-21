import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'admin/super_admin_dashboard.dart';
import 'agent/agent_screen.dart';
import 'analytics/analytics_screen.dart';
import 'auth/change_password_screen.dart';
import 'auth/login_screen.dart';
import 'auth/patient_login_screen.dart';
import 'auth/setup_wizard_screen.dart';
import 'call/inbox_screen.dart';
import 'camera/camera_screen.dart';
import 'camera/camera_status_service.dart';
import 'consultation/consultation_screen.dart';
import 'directory/people_directory_screen.dart';
import 'patient_portal/patient_dashboard_screen.dart';
import 'patient_portal/upload_report_screen.dart';
import 'profile/profile_screen.dart';
import 'providers/auth_provider.dart';
import 'providers/site_config_provider.dart';
import 'security/security_dashboard.dart';
import 'settings/analytics_screen.dart' as settings;
import 'settings/camera_management_screen.dart';
import 'settings/camera_settings_detail_screen.dart';
import 'settings/live_face_setup_screen.dart';
import 'settings/manage_staff_screen.dart';
import 'settings/rbac_mapper_screen.dart';
import 'settings/settings_screen.dart';
import 'widgets/shared_app_drawer.dart';
import 'indoor_tracking/tracking_status_banner.dart';
import 'indoor_tracking/indoor_tracking_screen.dart';
import 'indoor_tracking/floor_editor_screen.dart';
import 'indoor_tracking/hospital_geofence_screen.dart';

/// Paths reachable without being authenticated — the setup/login handoff,
/// and the pre-auth "Patient Portal (Demo)" flow linked from the login
/// screen. Everything else requires a session (see the redirect below).
bool _isPublicPath(String path) {
  return path == '/login' ||
      path == '/patient-login' ||
      path == '/setup' ||
      path.startsWith('/patient-demo');
}

/// One entry per top-level destination — the single source of truth for
/// the URL each tab lives at, the permission that gates it, and what the
/// side nav shows. Both the router (below) and SharedAppDrawer read this
/// list, so there's exactly one place to add a new top-level section.
class NavEntry {
  final String path;
  final String permission;
  final IconData icon;
  final String label;
  final Widget Function(GoRouterState state) builder;

  const NavEntry({
    required this.path,
    required this.permission,
    required this.icon,
    required this.label,
    required this.builder,
  });
}

const List<NavEntry> kNavEntries = [
  NavEntry(
    path: '/command-center',
    permission: 'view_admin',
    icon: Icons.grid_view,
    label: 'Command Center',
    builder: _superAdmin,
  ),
  NavEntry(
    path: '/directory',
    // Reuses the same permission the old top-level Patients tab used, so
    // anyone already granted access to that keeps access here with no RBAC
    // reconfiguration needed - the Directory is a superset (patients,
    // doctors, staff, all filterable via choice chips) of what that tab
    // showed, not a different capability.
    permission: 'view_patients',
    icon: Icons.people_alt_outlined,
    label: 'Directory',
    builder: _directory,
  ),
  NavEntry(
    // No permission gate (see AuthProvider.hasPermission's empty-string
    // case) - calling/messaging any other staff/admin account was never
    // RBAC-restricted to begin with (services/calls/authorization.can_call
    // is unconditional for staff<->staff/admin), only the People
    // Directory's browse view is. Without this, a doctor who got messaged
    // by an admin/superadmin (neither of whom has a Staff row, so neither
    // ever appears as a Directory card) had genuinely no way to discover
    // that message existed (/investigate 2026-09-19).
    path: '/inbox',
    permission: '',
    icon: Icons.inbox_outlined,
    label: 'Inbox',
    builder: _inbox,
  ),
  NavEntry(
    path: '/consultation',
    permission: 'view_consultation',
    icon: Icons.medical_services_outlined,
    label: 'Consultation',
    builder: _consultation,
  ),
  NavEntry(
    path: '/camera',
    permission: 'view_camera',
    icon: Icons.videocam_outlined,
    label: 'AI Camera',
    builder: _camera,
  ),
  NavEntry(
    path: '/analytics',
    permission: 'view_analytics',
    icon: Icons.analytics_outlined,
    label: 'AI Analytics',
    builder: _analytics,
  ),
  NavEntry(
    path: '/security',
    permission: 'view_security',
    icon: Icons.lock_outline,
    label: 'Security Vault',
    builder: _security,
  ),
  NavEntry(
    path: '/agent',
    permission: 'view_agent',
    icon: Icons.chat_bubble_outline,
    label: 'Agent',
    builder: _agent,
  ),
  NavEntry(
    path: '/indoor-tracking',
    permission: 'view_indoor_tracking',
    icon: Icons.map_outlined,
    label: 'Indoor Tracking',
    builder: _indoorTracking,
  ),
  NavEntry(
    path: '/settings',
    permission: 'view_settings',
    icon: Icons.settings_system_daydream_outlined,
    label: 'Settings',
    builder: _settings,
  ),
];

// Plain top-level functions (not closures) so `const` NavEntry literals
// above stay const-constructible.
Widget _superAdmin(GoRouterState state) => const SuperAdminDashboardScreen();
Widget _directory(GoRouterState state) => const PeopleDirectoryScreen();
Widget _inbox(GoRouterState state) => const InboxScreen();
Widget _consultation(GoRouterState state) => const ConsultationScreen();
Widget _camera(GoRouterState state) {
  // Security Vault's "View Cam" links here as /camera?expand=<id> instead
  // of pushing a second CameraScreen instance on top of this tab.
  final expand = state.uri.queryParameters['expand'];
  return CameraScreen(initialExpandedCameraId: _parseIntOrNull(expand));
}

int? _parseIntOrNull(String? raw) => raw == null ? null : int.tryParse(raw);
Widget _analytics(GoRouterState state) => const AnalyticsDashboardScreen();
Widget _security(GoRouterState state) => const SecurityDashboardScreen();
Widget _agent(GoRouterState state) => const AgentScreen();
Widget _settings(GoRouterState state) => const SettingsScreen();
Widget _indoorTracking(GoRouterState state) => const IndoorTrackingScreen();

/// Sub-pages reachable from within Settings. Each still shows the same
/// side nav (via SharedAppDrawer, unchanged) but isn't one of the primary
/// destinations — visiting one keeps "Settings" highlighted as active.
const String settingsStaffPath = '/settings/staff';
const String settingsCamerasPath = '/settings/cameras';
const String settingsRbacPath = '/settings/rbac';
const String settingsAnalyticsPath = '/settings/analytics';
const String settingsFloorEditorPath = '/settings/indoor-tracking/floors';
const String settingsGeofencePath = '/settings/indoor-tracking/geofence';

/// Maps a location to the permission required to view it. Falls back to
/// null (no gate) for anything not recognized, e.g. /login itself.
String? permissionForPath(String path) {
  if (path.startsWith('/settings')) return 'view_settings';
  // /patients/:id (a specific patient's full chart) is no longer a nav tab
  // itself (superseded by /directory), but it's still reachable directly
  // by URL/tap-through - without this explicit case it would fall through
  // to the loop below, match nothing, and end up ungated (any authenticated
  // user could view any patient's chart regardless of role).
  if (path.startsWith('/patients/')) return 'view_patients';
  for (final entry in kNavEntries) {
    if (path == entry.path || path.startsWith('${entry.path}/')) {
      return entry.permission;
    }
  }
  return null;
}

/// First destination this user actually has permission for — used to land
/// somewhere sensible after login, or when a route they can't access
/// redirects away instead of showing a blank/forbidden page.
String firstPermittedPath(AuthProvider auth) {
  for (final entry in kNavEntries) {
    if (auth.hasPermission(entry.permission)) return entry.path;
  }
  return '/no-access';
}

/// Root Navigator, distinct from each StatefulShellRoute branch's own
/// nested Navigator. Routes that should fully exit the shell (no side nav,
/// and — critically — a browser URL that actually updates) declare
/// `parentNavigatorKey: rootNavigatorKey` so go_router mounts them here
/// instead of inside whichever branch's nested Navigator the calling code
/// happened to be running in.
final rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter buildAppRouter(AuthProvider authProvider) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: authProvider,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final auth = authProvider;

      // Session restore is shown as a full-screen overlay by MaterialApp's
      // `builder`, not by redirecting — let the location resolve normally
      // underneath it so it's ready the instant restoration finishes.
      if (auth.isRestoringSession) return null;

      if (!auth.isAuthenticated) {
        return _isPublicPath(loc) ? null : '/login';
      }
      if (auth.mustChangePassword) {
        return loc == '/change-password' ? null : '/change-password';
      }

      // A patient-portal account has no RBAC permissions at all (patients
      // aren't staff), so the generic firstPermittedPath/permissionForPath
      // logic below would always dead-end at /no-access for them - route
      // patients to their own portal instead, and keep them there (no
      // access to any staff screen).
      if (auth.role == 'patient') {
        return loc.startsWith('/my-portal') ? null : '/my-portal';
      }

      if (loc == '/login' ||
          loc == '/patient-login' ||
          loc == '/setup' ||
          loc == '/change-password' ||
          loc == '/') {
        return firstPermittedPath(auth);
      }

      final requiredPermission = permissionForPath(loc);
      if (requiredPermission != null &&
          !auth.hasPermission(requiredPermission)) {
        return firstPermittedPath(auth);
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/patient-login',
        builder: (context, state) => const PatientLoginScreen(),
      ),
      GoRoute(
        path: '/setup',
        builder: (context, state) => const SetupWizardScreen(),
      ),
      GoRoute(
        path: '/change-password',
        builder: (context, state) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: '/no-access',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('No permissions assigned.')),
        ),
      ),
      // A real patient's own portal - patientId comes from their own
      // account (AuthProvider.patientId, set via /me), never from the URL.
      GoRoute(
        path: '/my-portal',
        builder: (context, state) {
          final patientId = context.watch<AuthProvider>().patientId;
          if (patientId == null) {
            return const Scaffold(
              body: Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text(
                    'This account has no patient profile linked to it. '
                    'Contact an administrator.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            );
          }
          return PatientDashboardScreen(patientId: patientId);
        },
        routes: [
          GoRoute(
            path: 'reports/upload',
            builder: (context, state) {
              final patientId = context.watch<AuthProvider>().patientId;
              return UploadReportScreen(patientId: patientId ?? 0);
            },
          ),
        ],
      ),
      // Pre-auth demo flow linked from the login screen — always patient
      // id 1, same as the hardcoded demo it replaced.
      GoRoute(
        path: '/patient-demo/:id',
        builder: (context, state) => PatientDashboardScreen(
          patientId: int.parse(state.pathParameters['id']!),
        ),
        routes: [
          GoRoute(
            path: 'reports/upload',
            builder: (context, state) => UploadReportScreen(
              patientId: int.parse(state.pathParameters['id']!),
            ),
          ),
        ],
      ),
      GoRoute(
        path: settingsStaffPath,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final enrollStaffId = state.uri.queryParameters['enrollRfidFor'];
          return ManageStaffScreen(
            autoEnrollRfidStaffId:
                enrollStaffId != null ? int.tryParse(enrollStaffId) : null,
            autoEnrollRfidStaffName: state.uri.queryParameters['staffName'],
          );
        },
        routes: [
          GoRoute(
            // Full path: /settings/staff/:id/live-setup
            path: ':id/live-setup',
            builder: (context, state) => LiveFaceSetupScreen(
              staffId: int.parse(state.pathParameters['id']!),
              isNewOnboarding:
                  state.uri.queryParameters['onboarding'] == 'true',
              staffName: state.uri.queryParameters['staffName'],
            ),
          ),
        ],
      ),
      GoRoute(
        path: settingsCamerasPath,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const CameraManagementScreen(),
        routes: [
          GoRoute(
            // Full path: /settings/cameras/:id
            path: ':id',
            builder: (context, state) => CameraSettingsDetailScreen(
              cameraId: int.parse(state.pathParameters['id']!),
            ),
          ),
        ],
      ),
      GoRoute(
        path: settingsRbacPath,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => RBACMapperScreen(
          initialRulesMode: state.uri.queryParameters['rulesMode'] == 'true',
        ),
      ),
      GoRoute(
        path: settingsAnalyticsPath,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const settings.AnalyticsScreen(),
      ),
      GoRoute(
        path: settingsFloorEditorPath,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const FloorEditorScreen(),
      ),
      GoRoute(
        path: settingsGeofencePath,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const HospitalGeofenceScreen(),
      ),
      GoRoute(
        path: '/profile',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ProfileScreen(),
      ),
      // A specific patient's full chart (reports + consultations) - reached
      // by tapping a patient card in the Directory. No longer nested under
      // a "Patients" shell branch (that tab was replaced by /directory),
      // so it's a standalone root-anchored route like the /settings/*
      // sub-pages above.
      GoRoute(
        path: '/patients/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => PatientDashboardScreen(
          patientId: int.parse(state.pathParameters['id']!),
        ),
        routes: [
          GoRoute(
            // Full path: /patients/:id/reports/upload
            path: 'reports/upload',
            builder: (context, state) => UploadReportScreen(
              patientId: int.parse(state.pathParameters['id']!),
            ),
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          for (final entry in kNavEntries)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: entry.path,
                  builder: (context, state) => entry.builder(state),
                ),
              ],
            ),
        ],
      ),
    ],
  );
}

/// Max number of destinations shown directly in the mobile bottom
/// NavigationBar before the rest collapse into a "More" sheet - Material 3
/// guidance is 3-5 destinations, and roles range from 2 tabs up to
/// SuperAdmin's 9, so a fixed cap plus overflow is the only shape that
/// looks right at every role's tab count.
const int _kMaxMobilePrimaryTabs = 4;

/// Persistent chrome (side nav + content area) for the primary
/// destinations, replacing the old index-based MainLayout. Each branch
/// keeps its own state alive via IndexedStack under the hood (switching
/// tabs doesn't drop camera WebSocket connections etc.), same as before —
/// the only thing that changed is that the active tab is now a real URL.
///
/// Desktop (>=900px) keeps the existing permanent sidebar. Mobile drops the
/// drawer/hamburger pattern entirely in favor of a bottom NavigationBar
/// (the convention users actually expect on a phone) built from the same
/// permission-filtered kNavEntries list the sidebar uses, so every role
/// automatically gets the right tabs with zero per-role special-casing.
class MainShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;
  const MainShell({super.key, required this.navigationShell});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  @override
  void initState() {
    super.initState();
    GlobalCameraStatus.startPolling();
  }

  @override
  void dispose() {
    GlobalCameraStatus.stopPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;

    if (isDesktop) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Row(
          children: [
            const SharedAppDrawer(),
            Expanded(
              child: Column(
                children: [
                  const TrackingStatusBanner(),
                  Expanded(child: widget.navigationShell),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final auth = context.watch<AuthProvider>();
    final visibleEntries =
        kNavEntries.where((e) => auth.hasPermission(e.permission)).toList();
    final primaryEntries = visibleEntries.take(_kMaxMobilePrimaryTabs).toList();
    final overflowEntries = visibleEntries.skip(_kMaxMobilePrimaryTabs).toList();
    final currentPath = GoRouterState.of(context).uri.path;

    int selectedIndex = primaryEntries.indexWhere(
        (e) => currentPath == e.path || currentPath.startsWith('${e.path}/'));
    final inOverflow = selectedIndex == -1 &&
        overflowEntries.any((e) => currentPath == e.path || currentPath.startsWith('${e.path}/'));
    if (selectedIndex == -1) selectedIndex = inOverflow ? primaryEntries.length : 0;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _MobileTopBar(),
            const TrackingStatusBanner(),
            Expanded(child: widget.navigationShell),
          ],
        ),
      ),
      bottomNavigationBar: (primaryEntries.length + overflowEntries.length) < 2
          ? null
          : NavigationBar(
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) {
                if (index < primaryEntries.length) {
                  context.go(primaryEntries[index].path);
                } else {
                  _showMoreSheet(context, overflowEntries);
                }
              },
              destinations: [
                for (final e in primaryEntries)
                  NavigationDestination(icon: Icon(e.icon), label: e.label),
                if (overflowEntries.isNotEmpty)
                  const NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
              ],
            ),
    );
  }

  void _showMoreSheet(BuildContext context, List<NavEntry> overflowEntries) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final e in overflowEntries)
              ListTile(
                leading: Icon(e.icon),
                title: Text(e.label),
                onTap: () {
                  Navigator.pop(ctx);
                  context.go(e.path);
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Compact mobile-only top bar: hospital branding on the left, a profile
/// avatar on the right (the standard convention for "go to my account" on
/// phones, decoupled from the bottom nav's tab count entirely). Replaces
/// the old floating hamburger button - this is also what was causing the
/// oversized top gap (a second, separate top-safe-area SizedBox stacked
/// underneath it); SafeArea on the Scaffold body now handles that once.
class _MobileTopBar extends StatelessWidget {
  const _MobileTopBar();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final siteConfig = context.watch<SiteConfigProvider>();
    final auth = context.watch<AuthProvider>();
    final displayName = auth.displayName ?? '';
    final initials = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: scheme.surfaceContainerLow,
      child: Row(
        children: [
          if (siteConfig.fullLogoUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(siteConfig.fullLogoUrl!, width: 28, height: 28, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(Icons.shield, color: scheme.secondary, size: 24)),
            )
          else
            Icon(Icons.shield, color: scheme.secondary, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              siteConfig.hospitalName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => context.push('/profile'),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: scheme.secondary.withValues(alpha: 0.15),
              child: Text(initials, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: scheme.secondary)),
            ),
          ),
        ],
      ),
    );
  }
}
