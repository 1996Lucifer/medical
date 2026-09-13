import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'reports_locker_screen.dart';
import 'consultations_screen.dart';
import 'patient_doctors_screen.dart';
import '../main.dart' show GlassBackground;
import '../network/api_routes.dart';
import '../network/network_manager.dart';
import '../providers/auth_provider.dart';

class PatientDashboardScreen extends StatefulWidget {
  final int patientId;
  const PatientDashboardScreen({super.key, required this.patientId});

  @override
  State<PatientDashboardScreen> createState() => _PatientDashboardScreenState();
}

class _PatientDashboardScreenState extends State<PatientDashboardScreen> {
  int _currentIndex = 0;
  List<dynamic> _chartData = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
  }

  Future<void> _fetchDashboardData() async {
    try {
      final response = await NetworkManager.instance.get(
          '${ApiRoutes.baseUrl}/api/patient-portal/dashboard/${widget.patientId}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _chartData = data['chart_data'];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildDashboard() {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.secondary;
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_chartData.isEmpty) {
      return Center(
        child: Text(
          "No health data available. Please upload reports.",
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    // Prepare chart data (Heart Rate)
    List<FlSpot> heartRateSpots = [];
    for (int i = 0; i < _chartData.length; i++) {
      var point = _chartData[i];
      var vitals = point['vitals'];
      if (vitals != null && vitals['heart_rate'] != null) {
        double hr = vitals['heart_rate'] is int
            ? (vitals['heart_rate'] as int).toDouble()
            : double.tryParse(vitals['heart_rate'].toString()) ?? 0;
        if (hr > 0) heartRateSpots.add(FlSpot(i.toDouble(), hr));
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Your Health Vitals",
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: scheme.onSurface,
                letterSpacing: -0.5),
          ),
          const SizedBox(height: 8),
          Text(
            "Heart rate trends over time based on your uploaded reports.",
            style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          if (heartRateSpots.isNotEmpty)
            Container(
              height: 300,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: 0.15),
                    accent.withValues(alpha: 0.03)
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: accent.withValues(alpha: 0.2)),
              ),
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(
                    rightTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: heartRateSpots,
                      isCurved: true,
                      color: accent,
                      barWidth: 4,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: accent.withValues(alpha: 0.2),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Center(
              child: Text("No heart rate data found in reports.",
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }

  static const List<_PatientNavEntry> _navEntries = [
    _PatientNavEntry('Dashboard', Icons.dashboard_outlined),
    _PatientNavEntry('Reports', Icons.medical_information_outlined),
    _PatientNavEntry('Consultations', Icons.history_edu),
    _PatientNavEntry('My Doctors', Icons.call_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final List<Widget> pages = [
      _buildDashboard(),
      ReportsLockerScreen(patientId: widget.patientId),
      ConsultationsScreen(patientId: widget.patientId),
      PatientDoctorsScreen(patientId: widget.patientId),
    ];

    // Reached via context.go() from the People Directory (/directory,
    // staff tapping a patient card to view their chart), the pre-auth demo
    // link on the login screen (/patient-demo), or a patient's own login
    // (/my-portal) — go() replaces the whole route stack, so there's
    // nothing for the default back button to pop to. /my-portal is a
    // patient's own home screen (nowhere to "go back" to except signing
    // out), so it and the demo both get a sign-out action instead of a
    // back arrow.
    final path = GoRouterState.of(context).uri.path;
    final isDemo = path.startsWith('/patient-demo');
    final isOwnPortal = path.startsWith('/my-portal');

    // Same responsive split as the staff app's MainShell: a permanently
    // visible sidebar on desktop (no click needed to open it), a
    // slide-in Drawer behind a hamburger button on mobile. This screen
    // previously always used the toggleable Drawer, even on desktop.
    final isDesktop = MediaQuery.of(context).size.width > 900;

    final content = Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        // Leave `leading` on its default on mobile so the Scaffold
        // auto-shows the drawer's hamburger button (an explicit `leading`
        // here would override that and make the drawer unreachable) - the
        // sign-out/back action goes in `actions` instead. On desktop
        // there's no `drawer:` set below, so this is just an unused slot.
        actions: [
          IconButton(
            icon: Icon(isOwnPortal ? Icons.logout : Icons.arrow_back),
            tooltip: isOwnPortal ? 'Sign out' : 'Back',
            onPressed: () {
              if (isOwnPortal) {
                context.read<AuthProvider>().logout();
              } else {
                context.go(isDemo ? '/login' : '/directory');
              }
            },
          ),
        ],
        title: Text(_navEntries[_currentIndex].label,
            style: TextStyle(
                fontWeight: FontWeight.bold, color: scheme.onSurface)),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: GlassBackground(child: pages[_currentIndex]),
      drawer: isDesktop
          ? null
          : Drawer(
              backgroundColor: scheme.surfaceContainerLow,
              child: SafeArea(
                child: _buildDrawerContent(context, closesOnTap: true),
              ),
            ),
    );

    if (!isDesktop) return content;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Row(
        children: [
          Container(
            width: 260,
            color: scheme.surfaceContainerLow,
            child: SafeArea(
              child: _buildDrawerContent(context, closesOnTap: false),
            ),
          ),
          Expanded(child: content),
        ],
      ),
    );
  }

  // Same visual language as the staff app's SharedAppDrawer (rounded logo
  // mark, teal left-border active indicator on a surface-tinted panel)
  // rather than the generic gradient-header Material Drawer this used
  // before - the patient portal is a different Scaffold tree from the
  // staff shell (go_router branch), so it can't literally reuse that
  // widget, but it should still look and behave like the same product.
  // `closesOnTap` is true when this is rendered inside a slide-in Drawer
  // (mobile - selecting an item should close it) and false when it's the
  // permanent desktop sidebar (nothing to close).
  Widget _buildDrawerContent(BuildContext context,
      {required bool closesOnTap}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              Icon(Icons.favorite_outline, color: scheme.secondary, size: 40),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Patient Portal',
                  style: TextStyle(
                    color: scheme.secondary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < _navEntries.length; i++)
          _drawerItem(
            context,
            entry: _navEntries[i],
            isActive: _currentIndex == i,
            onTap: () {
              if (closesOnTap) Navigator.pop(context);
              setState(() {
                _currentIndex = i;
                if (i == 0) _fetchDashboardData();
              });
            },
          ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: InkWell(
            onTap: () {
              if (closesOnTap) Navigator.pop(context);
              context.read<AuthProvider>().logout();
            },
            child: Row(
              children: [
                Icon(Icons.logout, color: Colors.red[300], size: 20),
                const SizedBox(width: 12),
                Text('Sign Out',
                    style: TextStyle(
                        color: Colors.red[300], fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _drawerItem(
    BuildContext context, {
    required _PatientNavEntry entry,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isActive
              ? scheme.secondary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isActive
              ? Border(left: BorderSide(color: scheme.secondary, width: 3))
              : null,
        ),
        child: Row(
          children: [
            Icon(entry.icon,
                color: isActive ? scheme.secondary : scheme.onSurfaceVariant,
                size: 24),
            const SizedBox(width: 16),
            Text(
              entry.label,
              style: TextStyle(
                color: isActive ? scheme.secondary : scheme.onSurfaceVariant,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientNavEntry {
  final String label;
  final IconData icon;
  const _PatientNavEntry(this.label, this.icon);
}
