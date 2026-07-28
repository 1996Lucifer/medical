import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'admin/super_admin_dashboard.dart';
import 'agent/agent_screen.dart';
import 'analytics/analytics_screen.dart';
import 'auth/login_screen.dart';
import 'camera/camera_screen.dart';
import 'camera/camera_status_service.dart';
import 'consultation/consultation_screen.dart';
import 'network/environment.dart';
import 'patients/patients_list_screen.dart';
import 'security/security_dashboard.dart';
import 'settings/settings_screen.dart';
import 'widgets/shared_app_drawer.dart';

import 'providers/auth_provider.dart';
import 'providers/agent_provider.dart';
import 'providers/consultation_provider.dart';
import 'providers/camera_provider.dart';
import 'providers/analytics_provider.dart';
import 'providers/security_provider.dart';
import 'providers/site_config_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EnvironmentConfig.init();

  final authProvider = AuthProvider();
  final siteConfigProvider = SiteConfigProvider();
  // Kick off session restoration from persisted JWT before first frame
  authProvider.tryAutoLogin();
  // Load hospital branding config
  siteConfigProvider.fetchConfig();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: siteConfigProvider),
        ChangeNotifierProvider(create: (_) => AgentProvider()),
        ChangeNotifierProvider(create: (_) => ConsultationProvider()),
        ChangeNotifierProvider(create: (_) => CameraProvider()),
        ChangeNotifierProvider(create: (_) => AnalyticsProvider()),
        ChangeNotifierProvider(create: (_) => SecurityProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Healthcare Operations Copilot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F172A), // Dark slate
          primary: const Color(0xFF38BDF8), // Light blue for accents
          secondary: const Color(0xFF2DD4BF), // Teal for secondary accents
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.transparent,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      home: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          // Show a splash screen while we check for a persisted JWT
          if (auth.isRestoringSession) {
            return Consumer<SiteConfigProvider>(
              builder: (context, siteConfig, _) {
                return Scaffold(
                  backgroundColor: const Color(0xFF041329),
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (siteConfig.fullLogoUrl != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              siteConfig.fullLogoUrl!,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.shield, size: 56, color: Color(0xFF38debb)),
                            ),
                          )
                        else
                          const Icon(Icons.shield, size: 56, color: Color(0xFF38debb)),
                        const SizedBox(height: 24),
                        Text(
                          siteConfig.hospitalName,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Color(0xFF38debb),
                            strokeWidth: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
            );
          }
          return auth.isAuthenticated
              ? MainLayout()
              : const LoginScreen();
        },
      ),
    );
  }
}

final GlobalKey<MainLayoutState> mainLayoutKey = GlobalKey<MainLayoutState>();

class MainLayout extends StatefulWidget {
  MainLayout({Key? key}) : super(key: mainLayoutKey);

  @override
  State<MainLayout> createState() => MainLayoutState();
}

class MainLayoutState extends State<MainLayout> {
  int currentIndex = 0;

  void changeTab(int index) {
    setState(() {
      currentIndex = index;
    });
  }

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
    final auth = context.watch<AuthProvider>();
    final isDesktop = MediaQuery.of(context).size.width > 900;

    final List<Widget> screens = [];
    final List<NavigationDestination> destinations = [];

    if (auth.hasPermission('view_admin')) {
      screens.add(const SuperAdminDashboardScreen());
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.grid_view),
        label: 'Command Center',
      ));
    }

    if (auth.hasPermission('view_patients')) {
      screens.add(const PatientsListScreen());
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.people_alt_outlined),
        label: 'Patients',
      ));
    }

    if (auth.hasPermission('view_consultation')) {
      screens.add(const ConsultationScreen());
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.medical_services_outlined),
        label: 'Consultation',
      ));
    }

    if (auth.hasPermission('view_camera')) {
      screens.add(const CameraScreen());
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.videocam_outlined),
        label: 'AI Camera',
      ));
    }

    if (auth.hasPermission('view_analytics')) {
      screens.add(const AnalyticsDashboardScreen());
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.analytics_outlined),
        label: 'AI Analytics',
      ));
    }

    if (auth.hasPermission('view_security')) {
      screens.add(const SecurityDashboardScreen());
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.lock_outline),
        label: 'Security Vault',
      ));
    }

    if (auth.hasPermission('view_agent')) {
      screens.add(const AgentScreen());
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.chat_bubble_outline),
        label: 'Agent',
      ));
    }

    if (auth.hasPermission('view_settings')) {
      screens.add(const SettingsScreen());
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.settings_system_daydream_outlined),
        label: 'System Health',
      ));
    }

    if (screens.isEmpty) {
      screens.add(const Center(child: Text("No permissions assigned.")));
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.error),
        label: 'No Access',
      ));
    }

    if (currentIndex >= screens.length) {
      currentIndex = 0;
    }

    Widget content = IndexedStack(
      index: currentIndex,
      children: screens,
    );

    if (isDesktop) {
      return Scaffold(
        backgroundColor: const Color(0xFF041329), // Aetheris background
        body: Row(
          children: [
            SharedAppDrawer(
              currentIndex: currentIndex,
              onIndexChanged: changeTab,
            ),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF041329),
      drawer: Drawer(
        backgroundColor: const Color(0xFF071A33),
        child: SharedAppDrawer(
          currentIndex: currentIndex,
          onIndexChanged: changeTab,
        ),
      ),
      body: Stack(
        children: [
          content,
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu, color: Colors.white, shadows: [
                  Shadow(color: Colors.black54, blurRadius: 4)
                ]),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Glassmorphic UI helpers ──────────────────────────────────────────────────

class GlassCard extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;

  const GlassCard({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = 12.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 30,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
          child: Container(
            padding: padding ?? const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: const Color(0xFF112036).withValues(alpha: 0.6), // surface-container
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1.0,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class GlassBackground extends StatelessWidget {
  final Widget child;

  const GlassBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          color: const Color(0xFF041329), // Background color
        ),
        Positioned(
          top: -100,
          right: -100,
          child: Container(
            width: 600,
            height: 600,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF38debb).withValues(alpha: 0.05), // Primary-fixed-dim leak
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 120.0, sigmaY: 120.0),
              child: Container(color: Colors.transparent),
            ),
          ),
        ),
        Positioned(
          bottom: 80,
          left: 40,
          child: Container(
            width: 400,
            height: 400,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF14d1ff).withValues(alpha: 0.05), // Secondary-container leak
            ),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 100.0, sigmaY: 100.0),
              child: Container(color: Colors.transparent),
            ),
          ),
        ),
        SafeArea(child: child),
      ],
    );
  }
}
