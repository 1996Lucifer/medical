import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'admin/super_admin_dashboard.dart';
import 'agent/agent_screen.dart';
import 'analytics/analytics_screen.dart';
import 'auth/change_password_screen.dart';
import 'auth/login_screen.dart';
import 'auth/setup_wizard_screen.dart';
import 'camera/camera_screen.dart';
import 'camera/camera_status_service.dart';
import 'consultation/consultation_screen.dart';
import 'patient_portal/patient_dashboard_screen.dart';
import 'patient_portal/upload_report_screen.dart';
import 'patients/patients_list_screen.dart';
import 'providers/auth_provider.dart';
import 'security/security_dashboard.dart';
import 'settings/analytics_screen.dart' as settings;
import 'settings/camera_management_screen.dart';
import 'settings/camera_settings_detail_screen.dart';
import 'settings/live_face_setup_screen.dart';
import 'settings/manage_staff_screen.dart';
import 'settings/rbac_mapper_screen.dart';
import 'settings/settings_screen.dart';
import 'widgets/shared_app_drawer.dart';

/// Paths reachable without being authenticated — the setup/login handoff,
/// and the pre-auth "Patient Portal (Demo)" flow linked from the login
/// screen. Everything else requires a session (see the redirect below).
bool _isPublicPath(String path) {
  return path == '/login' || path == '/setup' || path.startsWith('/patient-demo');
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
    path: '/patients',
    permission: 'view_patients',
    icon: Icons.people_alt_outlined,
    label: 'Patients',
    builder: _patients,
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
Widget _patients(GoRouterState state) => PatientsListScreen();
Widget _consultation(GoRouterState state) => ConsultationScreen();
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
Widget _settings(GoRouterState state) => SettingsScreen();

/// Sub-pages reachable from within Settings. Each still shows the same
/// side nav (via SharedAppDrawer, unchanged) but isn't one of the primary
/// destinations — visiting one keeps "Settings" highlighted as active.
const String settingsStaffPath = '/settings/staff';
const String settingsCamerasPath = '/settings/cameras';
const String settingsRbacPath = '/settings/rbac';
const String settingsAnalyticsPath = '/settings/analytics';

/// Maps a location to the permission required to view it. Falls back to
/// null (no gate) for anything not recognized, e.g. /login itself.
String? permissionForPath(String path) {
  if (path.startsWith('/settings')) return 'view_settings';
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
      if (loc == '/login' ||
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
        builder: (context, state) => const ManageStaffScreen(),
        routes: [
          GoRoute(
            // Full path: /settings/staff/:id/live-setup
            path: ':id/live-setup',
            builder: (context, state) => LiveFaceSetupScreen(
              staffId: int.parse(state.pathParameters['id']!),
            ),
          ),
        ],
      ),
      GoRoute(
        path: settingsCamerasPath,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => CameraManagementScreen(),
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
                  routes: entry.path == '/patients'
                      ? [
                          GoRoute(
                            // Full path: /patients/:id
                            path: ':id',
                            parentNavigatorKey: rootNavigatorKey,
                            builder: (context, state) =>
                                PatientDashboardScreen(
                              patientId:
                                  int.parse(state.pathParameters['id']!),
                            ),
                            routes: [
                              GoRoute(
                                // Full path: /patients/:id/reports/upload
                                path: 'reports/upload',
                                builder: (context, state) =>
                                    UploadReportScreen(
                                  patientId:
                                      int.parse(state.pathParameters['id']!),
                                ),
                              ),
                            ],
                          ),
                        ]
                      : const [],
                ),
              ],
            ),
        ],
      ),
    ],
  );
}

/// Persistent chrome (side nav + content area) for the 8 primary
/// destinations, replacing the old index-based MainLayout. Each branch
/// keeps its own state alive via IndexedStack under the hood (switching
/// tabs doesn't drop camera WebSocket connections etc.), same as before —
/// the only thing that changed is that the active tab is now a real URL.
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
            Expanded(child: widget.navigationShell),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: Drawer(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        child: const SharedAppDrawer(),
      ),
      body: Stack(
        children: [
          widget.navigationShell,
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)]),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
