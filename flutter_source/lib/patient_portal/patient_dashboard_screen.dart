import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'reports_locker_screen.dart';
import 'consultations_screen.dart';
import '../network/api_routes.dart';

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
      final response = await http.get(Uri.parse('${ApiRoutes.baseUrl}/api/patient-portal/dashboard/${widget.patientId}'));
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
                  colors: [Colors.blue.withValues(alpha: 0.1), Colors.purple.withValues(alpha: 0.1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
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
                      color: Colors.blue,
                      barWidth: 4,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.blue.withValues(alpha: 0.2),
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
    final List<Widget> pages = [
      _buildDashboard(),
      ReportsLockerScreen(patientId: widget.patientId),
      ConsultationsScreen(patientId: widget.patientId),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient Portal'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
            if (index == 0) _fetchDashboardData();
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: "Dashboard"),
          NavigationDestination(icon: Icon(Icons.medical_information_outlined), label: "Reports"),
          NavigationDestination(icon: Icon(Icons.history_edu), label: "Consultations"),
        ],
      ),
    );
  }
}
