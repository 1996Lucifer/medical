import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'reports_locker_screen.dart';
import 'consultations_screen.dart';
import '../network/api_routes.dart';
import '../network/network_manager.dart';

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
      final response = await NetworkManager.instance.get('${ApiRoutes.baseUrl}/api/patient-portal/dashboard/${widget.patientId}');
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
    final accent = Theme.of(context).colorScheme.secondary;
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_chartData.isEmpty) {
      return const Center(child: Text("No health data available. Please upload reports."));
    }

    // Prepare chart data (Heart Rate)
    List<FlSpot> heartRateSpots = [];
    for (int i = 0; i < _chartData.length; i++) {
      var point = _chartData[i];
      var vitals = point['vitals'];
      if (vitals != null && vitals['heart_rate'] != null) {
        double hr = vitals['heart_rate'] is int ? (vitals['heart_rate'] as int).toDouble() : double.tryParse(vitals['heart_rate'].toString()) ?? 0;
        if (hr > 0) heartRateSpots.add(FlSpot(i.toDouble(), hr));
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Your Health Vitals",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text("Heart rate trends over time based on your uploaded reports."),
          const SizedBox(height: 24),

          if (heartRateSpots.isNotEmpty)
            Container(
              height: 300,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [accent.withValues(alpha: 0.15), accent.withValues(alpha: 0.03)],
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
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
            const Center(child: Text("No heart rate data found in reports.")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onAccent = ThemeData.estimateBrightnessForColor(scheme.secondary) ==
            Brightness.dark
        ? Colors.white
        : Colors.black87;
    final List<Widget> pages = [
      _buildDashboard(),
      ReportsLockerScreen(patientId: widget.patientId),
      ConsultationsScreen(patientId: widget.patientId),
    ];

    // Reached via context.go() from either the real, authenticated patient
    // list (/patients) or the pre-auth demo link on the login screen
    // (/patient-demo) — go() replaces the whole route stack, so there's
    // nothing for the default back button to pop to; send it back to
    // whichever parent this instance was actually opened from.
    final isDemo =
        GoRouterState.of(context).uri.path.startsWith('/patient-demo');
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(isDemo ? '/login' : '/patients'),
        ),
        title: const Text('Patient Portal'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: pages[_currentIndex],
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scheme.secondary, scheme.primaryContainer],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.local_hospital, color: onAccent, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Patient Portal',
                    style: TextStyle(
                      color: onAccent,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.dashboard_outlined, color: _currentIndex == 0 ? scheme.secondary : null),
              title: Text("Dashboard", style: TextStyle(fontWeight: _currentIndex == 0 ? FontWeight.bold : FontWeight.normal)),
              selected: _currentIndex == 0,
              selectedTileColor: scheme.secondary.withValues(alpha: 0.1),
              onTap: () {
                setState(() {
                  _currentIndex = 0;
                  _fetchDashboardData();
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.medical_information_outlined, color: _currentIndex == 1 ? scheme.secondary : null),
              title: Text("Reports", style: TextStyle(fontWeight: _currentIndex == 1 ? FontWeight.bold : FontWeight.normal)),
              selected: _currentIndex == 1,
              selectedTileColor: scheme.secondary.withValues(alpha: 0.1),
              onTap: () {
                setState(() {
                  _currentIndex = 1;
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.history_edu, color: _currentIndex == 2 ? scheme.secondary : null),
              title: Text("Consultations", style: TextStyle(fontWeight: _currentIndex == 2 ? FontWeight.bold : FontWeight.normal)),
              selected: _currentIndex == 2,
              selectedTileColor: scheme.secondary.withValues(alpha: 0.1),
              onTap: () {
                setState(() {
                  _currentIndex = 2;
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
