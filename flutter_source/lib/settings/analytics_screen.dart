import 'dart:convert';

import 'package:flutter/material.dart';

import '../network/api_routes.dart';
import '../network/network_manager.dart';

const Color _bgBase = Color(0xFF041329);
const Color _surfaceContainer = Color(0xFF112036);
const Color _surfaceContainerLow = Color(0xFF0d1c32);
const Color _surfaceContainerHigh = Color(0xFF1c2a41);
const Color _surfaceContainerHighest = Color(0xFF27354c);
const Color _tealAccent = Color(0xFF38debb);
const Color _tealAccentDim = Color(0xFF00725e);
const Color _blueAccent = Color(0xFF4cd6ff);
const Color _textColor = Color(0xFFd6e3ff);
const Color _textVariant = Color(0xFFbacac3);
const Color _critical = Color(0xFFffb4ab);
const Color _outlineVariant = Color(0xFF3c4a45);

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Map<String, List<dynamic>> _attendanceSummary = {};
  List<dynamic> _recentEvents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final Future<void> attendanceFuture = NetworkManager.instance
          .get(ApiRoutes.attendanceSummary(7))
          .then((resp) {
        if (resp.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(resp.body);
          final Map<String, dynamic> raw = data.containsKey('summary')
              ? data['summary'] as Map<String, dynamic>
              : data;
          _attendanceSummary =
              raw.map((k, v) => MapEntry(k, v as List<dynamic>));
        }
      });

      final Future<void> eventsFuture = NetworkManager.instance
          .get(ApiRoutes.analyticsEvents(30))
          .then((resp) {
        if (resp.statusCode == 200) {
          _recentEvents = jsonDecode(resp.body) as List<dynamic>;
        }
      });

      await Future.wait([attendanceFuture, eventsFuture]);
    } catch (e) {
      debugPrint('Error fetching analytics: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgBase,
      appBar: AppBar(
        title: const Text('Analytics Engine Configuration',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: OutlinedButton(
              onPressed: () {},
              style: OutlinedButton.styleFrom(
                foregroundColor: _textVariant,
                side: const BorderSide(color: _outlineVariant),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('DIAGNOSTICS',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: ElevatedButton.icon(
              onPressed: _fetchData,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('REFRESH',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _tealAccent,
                foregroundColor: _bgBase,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _tealAccent))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'Fine-tune real-time efficiency metrics and configure AI detection parameters for secure facility monitoring.',
                        style: TextStyle(color: _textVariant, fontSize: 16)),
                    const SizedBox(height: 32),
                    LayoutBuilder(builder: (context, constraints) {
                      if (constraints.maxWidth > 900) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 5, child: _buildLeftColumn()),
                            const SizedBox(width: 24),
                            Expanded(flex: 7, child: _buildRightColumn()),
                          ],
                        );
                      }
                      return Column(
                        children: [
                          _buildLeftColumn(),
                          const SizedBox(height: 24),
                          _buildRightColumn(),
                        ],
                      );
                    }),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildLeftColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(Icons.sensors, 'Real-Time Metrics'),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              color: _surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: _outlineVariant.withValues(alpha: 0.5))),
          child: Column(
            children: [
              _buildToggleRow('Patient Flow Analytics',
                  'Ward and ER movement tracking.', true),
              const SizedBox(height: 16),
              _buildToggleRow('Staff Efficiency Tracking',
                  'Response times and shift loads.', true),
              const SizedBox(height: 16),
              _buildToggleRow('Resource Allocation AI',
                  'Predictive supply management.', false),
            ],
          ),
        ),
        const SizedBox(height: 32),
        _buildSectionHeader(Icons.settings_suggest, 'Log Parameters'),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              color: _surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: _outlineVariant.withValues(alpha: 0.5))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('AI SENSITIVITY LEVEL',
                      style: TextStyle(
                          color: _tealAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5)),
                  Text('85%',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  activeTrackColor: _tealAccent,
                  inactiveTrackColor: _surfaceContainerHigh,
                  thumbColor: _tealAccent,
                  overlayColor: _tealAccent.withValues(alpha: 0.2),
                ),
                child: Slider(value: 85, min: 0, max: 100, onChanged: (v) {}),
              ),
              const SizedBox(height: 24),
              const Text('RETENTION POLICY',
                  style: TextStyle(
                      color: _tealAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5)),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                    color: _surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: _outlineVariant.withValues(alpha: 0.5))),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('30 Days (Standard Compliance)',
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                    Icon(Icons.expand_more, color: _textVariant, size: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRightColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              color: _surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: _outlineVariant.withValues(alpha: 0.5))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSectionHeader(Icons.query_stats, 'Engine Visualization',
                      noPadding: true),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: _surfaceContainerLow,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: _outlineVariant.withValues(alpha: 0.5))),
                    child: Row(
                      children: [
                        Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                                color: _critical,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(color: _critical, blurRadius: 4)
                                ])),
                        const SizedBox(width: 8),
                        const Text('LIVE TRANSMISSION',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildChartMockup(),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: _buildStatBox('Efficiency', '94.2%')),
                  const SizedBox(width: 16),
                  Expanded(
                      child:
                          _buildStatBox('Latency', '24ms', color: _blueAccent)),
                  const SizedBox(width: 16),
                  Expanded(
                      child: _buildStatBox('Anomalies', '2', color: _critical)),
                ],
              )
            ],
          ),
        ),
        const SizedBox(height: 32),
        Container(
          decoration: BoxDecoration(
              color: _surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: _outlineVariant.withValues(alpha: 0.5))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildSectionHeader(
                        Icons.list_alt, 'Intelligence Feed & Audit Logs',
                        noPadding: true),
                    const Text('FULL AUDIT',
                        style: TextStyle(
                            color: _tealAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5)),
                  ],
                ),
              ),
              const Divider(height: 1, color: _outlineVariant),
              _buildEventsTable(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(IconData icon, String title,
      {bool noPadding = false}) {
    return Row(
      children: [
        Icon(icon, color: _tealAccent, size: 20),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildToggleRow(String title, String subtitle, bool isToggled) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(color: _textVariant, fontSize: 12)),
            ],
          ),
        ),
        Container(
          width: 44,
          height: 24,
          decoration: BoxDecoration(
              color: isToggled ? _tealAccent : _surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.all(2),
          alignment: isToggled ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle)),
        )
      ],
    );
  }

  Widget _buildStatBox(String title, String value, {Color? color}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: _surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _outlineVariant.withValues(alpha: 0.5))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: const TextStyle(
                  color: _textVariant,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: color ?? _tealAccent,
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildChartMockup() {
    return Column(
      children: [
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _bar(0.45, _blueAccent.withValues(alpha: 0.4)),
              _bar(0.65, _blueAccent.withValues(alpha: 0.6)),
              _bar(0.85, _tealAccent),
              _bar(0.55, _blueAccent.withValues(alpha: 0.5)),
              _bar(0.40, _blueAccent.withValues(alpha: 0.3)),
              _bar(0.75, _blueAccent.withValues(alpha: 0.7)),
              _bar(0.95, _tealAccent),
              _bar(0.35, _blueAccent.withValues(alpha: 0.2)),
              _bar(0.60, _blueAccent.withValues(alpha: 0.5)),
              _bar(0.50, _blueAccent.withValues(alpha: 0.4)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('08:00',
                style: TextStyle(
                    color: _textVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
            Text('10:00',
                style: TextStyle(
                    color: _textVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
            Text('12:00',
                style: TextStyle(
                    color: _textVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
            Text('14:00',
                style: TextStyle(
                    color: _textVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
            Text('16:00',
                style: TextStyle(
                    color: _textVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
          ],
        )
      ],
    );
  }

  Widget _bar(double fill, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        child: FractionallySizedBox(
          heightFactor: fill,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEventsTable() {
    if (_recentEvents.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32.0),
        child: Center(
            child: Text('No system events recorded yet.',
                style: TextStyle(color: _textVariant))),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _recentEvents.length > 5 ? 5 : _recentEvents.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, color: _outlineVariant),
      itemBuilder: (context, index) {
        final event = _recentEvents[index];
        final type = event['event_type'];
        final isAlert = type == 'UnknownFaceDetected' ||
            type == 'CameraOffline' ||
            type == 'SecurityAlert';

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Row(
            children: [
              SizedBox(
                width: 70,
                child: Text(
                    event['timestamp']?.split('T').last.substring(0, 8) ??
                        '00:00:00',
                    style: const TextStyle(
                        color: _textVariant,
                        fontSize: 12,
                        fontFamily: 'monospace')),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(type,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    Text('${event['camera_name'] ?? 'System Hub'}',
                        style:
                            const TextStyle(color: _textVariant, fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isAlert
                      ? _critical.withValues(alpha: 0.1)
                      : _tealAccent.withValues(alpha: 0.1),
                  border: Border.all(
                      color: isAlert
                          ? _critical.withValues(alpha: 0.3)
                          : _tealAccent.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isAlert ? 'PENDING' : 'VERIFIED',
                  style: TextStyle(
                      color: isAlert ? _critical : _tealAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
