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
import 'security/security_dashboard.dart';
import 'settings/settings_screen.dart';

import 'providers/auth_provider.dart';
import 'providers/agent_provider.dart';
import 'providers/consultation_provider.dart';
import 'providers/camera_provider.dart';
import 'providers/analytics_provider.dart';
import 'providers/security_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EnvironmentConfig.init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A), // Deep medical blue
          primary: const Color(0xFF1E3A8A),
          secondary: Colors.teal.shade600,
        ),
        useMaterial3: true,
      ),
      home: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          return auth.isAuthenticated
              ? const MainLayout()
              : const LoginScreen();
        },
      ),
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;

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
    
    final List<Widget> screens = [];
    final List<NavigationDestination> destinations = [];

    if (auth.hasPermission('view_admin')) {
      screens.add(const SuperAdminDashboardScreen());
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.admin_panel_settings_outlined),
        selectedIcon: Icon(Icons.admin_panel_settings),
        label: 'Admin',
      ));
    }

    if (auth.hasPermission('view_consultation')) {
      screens.add(const ConsultationScreen());
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.medical_services_outlined),
        selectedIcon: Icon(Icons.medical_services),
        label: 'Consultation',
      ));
    }

    if (auth.hasPermission('view_camera')) {
      screens.add(const CameraScreen());
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.videocam_outlined),
        selectedIcon: Icon(Icons.videocam),
        label: 'AI Camera',
      ));
    }

    if (auth.hasPermission('view_analytics')) {
      screens.add(const AnalyticsDashboardScreen());
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.bar_chart_outlined),
        selectedIcon: Icon(Icons.bar_chart),
        label: 'Analytics',
      ));
    }

    if (auth.hasPermission('view_security')) {
      screens.add(const SecurityDashboardScreen());
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.security_outlined),
        selectedIcon: Icon(Icons.security),
        label: 'Security',
      ));
    }

    if (auth.hasPermission('view_agent')) {
      screens.add(const AgentScreen());
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.chat_bubble_outline),
        selectedIcon: Icon(Icons.chat_bubble),
        label: 'Agent',
      ));
    }

    if (auth.hasPermission('view_settings')) {
      screens.add(const SettingsScreen());
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: 'Settings',
      ));
    }

    if (screens.isEmpty) {
      screens.add(const Center(child: Text("No permissions assigned.")));
      destinations.add(const NavigationDestination(
        icon: Icon(Icons.error),
        label: 'No Access',
      ));
    }

    if (_currentIndex >= screens.length) {
      _currentIndex = 0;
    }

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: destinations,
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
    this.borderRadius = 16.0,
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
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Container(
        padding: padding ?? const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.6),
            width: 1.5,
          ),
        ),
        child: child,
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
          color:
              const Color(0xFFF8FAFC), // Lighter slate for cleaner medical look
        ),
        Positioned(
          top: -80,
          right: -80,
          child: Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.teal.shade100.withValues(alpha: 0.45),
            ),
          ),
        ),
        Positioned(
          bottom: -100,
          left: -100,
          child: Container(
            width: 380,
            height: 380,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1E3A8A)
                  .withValues(alpha: 0.12), // Medical Blue
            ),
          ),
        ),
        const Positioned.fill(
          child: Center(
            child: Opacity(
              opacity: 0.04,
              child: Icon(Icons.local_hospital,
                  size: 350, color: Color(0xFF1E3A8A)),
            ),
          ),
        ),
        SafeArea(child: child),
      ],
    );
  }
}
