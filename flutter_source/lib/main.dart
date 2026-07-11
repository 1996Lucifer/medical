import 'package:flutter/material.dart';

import 'agent/agent_screen.dart';
import 'analytics/analytics_screen.dart';
import 'auth/login_screen.dart';
import 'camera/camera_screen.dart';
import 'camera/camera_status_service.dart';
import 'consultation/consultation_screen.dart';
import 'network/environment.dart';
import 'security/security_dashboard.dart';
import 'settings/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EnvironmentConfig.init();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isAuthenticated = false;

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
      home: _isAuthenticated
          ? const MainLayout()
          : LoginScreen(onLoginSuccess: () {
              setState(() {
                _isAuthenticated = true;
              });
            }),
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
  final List<Widget> _screens = [
    const ConsultationScreen(),
    const CameraScreen(),
    const AnalyticsDashboardScreen(),
    const SecurityDashboardScreen(),
    const AgentScreen(),
    const SettingsScreen(),
  ];

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
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.medical_services_outlined),
            selectedIcon: Icon(Icons.medical_services),
            label: 'Consultation',
          ),
          NavigationDestination(
            icon: Icon(Icons.videocam_outlined),
            selectedIcon: Icon(Icons.videocam),
            label: 'AI Camera',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Analytics',
          ),
          NavigationDestination(
            icon: Icon(Icons.security_outlined),
            selectedIcon: Icon(Icons.security),
            label: 'Security',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Agent',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
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
            color: Colors.black.withOpacity(0.03),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Container(
        padding: padding ?? const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: Colors.white.withOpacity(0.6),
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
              color: Colors.teal.shade100.withOpacity(0.45),
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
              color: const Color(0xFF1E3A8A).withOpacity(0.12), // Medical Blue
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
