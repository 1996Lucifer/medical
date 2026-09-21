import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../network/api_routes.dart';
import '../network/network_manager.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Map<String, List<dynamic>> _attendanceSummary = {};
  Map<String, List<dynamic>> _shiftCompliance = {};
  List<dynamic> _recentEvents = [];
  bool _isLoading = true;
  DateTime? _lastFetched;
  String? _fetchError;

  // Theme-derived colors
  Color get _bgBase => Theme.of(context).scaffoldBackgroundColor;
  Color get _surfaceContainer => Theme.of(context).colorScheme.surfaceContainer;
  Color get _surfaceContainerLow => Theme.of(context).colorScheme.surfaceContainerLow;
  Color get _surfaceContainerHigh => Theme.of(context).colorScheme.surfaceContainerHigh;
  Color get _surfaceContainerHighest => Theme.of(context).colorScheme.surfaceContainerHighest;
  Color get _tealAccent => Theme.of(context).colorScheme.secondary;
  Color get _blueAccent => Theme.of(context).colorScheme.tertiary;
  Color get _textColor => Theme.of(context).colorScheme.onSurface;
  Color get _textVariant => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _critical => Theme.of(context).colorScheme.error;
  Color get _outlineVariant => Theme.of(context).colorScheme.outlineVariant;

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
          if (data['shift_compliance'] != null) {
            _shiftCompliance = (data['shift_compliance'] as Map<String, dynamic>)
                .map((k, v) => MapEntry(k, v as List<dynamic>));
          }
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
      _fetchError = null;
    } catch (e) {
      debugPrint('Error fetching analytics: $e');
      _fetchError = e.toString();
    } finally {
      _lastFetched = DateTime.now();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showDiagnostics() {
    final totalAttendanceRecords =
        _attendanceSummary.values.fold<int>(0, (sum, l) => sum + l.length);
    final rows = <MapEntry<String, String>>[
      MapEntry('API base URL', ApiRoutes.baseUrl),
      MapEntry('Last data refresh',
          _lastFetched?.toLocal().toString() ?? 'Never'),
      MapEntry('Last refresh status', _fetchError == null ? 'OK' : 'Failed'),
      if (_fetchError != null) MapEntry('Last error', _fetchError!),
      MapEntry('Staff tracked (attendance)',
          _attendanceSummary.keys.length.toString()),
      MapEntry('Attendance records loaded', totalAttendanceRecords.toString()),
      MapEntry('Recent events loaded', _recentEvents.length.toString()),
    ];

    showDialog(
      context: context,
      builder: (ctx) => Theme(
        data: Theme.of(context)
            .copyWith(dialogTheme: DialogThemeData(backgroundColor: _surfaceContainer)),
        child: AlertDialog(
          title: Text('Diagnostics', style: TextStyle(color: _textColor)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: rows
                  .map((r) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 170,
                              child: Text(r.key,
                                  style: TextStyle(
                                      color: _textVariant, fontSize: 12)),
                            ),
                            Expanded(
                              child: Text(r.value,
                                  style: TextStyle(
                                      color: _textColor, fontSize: 12)),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Close', style: TextStyle(color: _tealAccent)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgBase,
      appBar: AppBar(
        // Reached via context.go(), which replaces the whole route stack —
        // there's nothing for the default back button to pop to.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/settings'),
        ),
        title: Text('Analytics Engine Configuration',
            style: TextStyle(fontWeight: FontWeight.bold, color: _textColor)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: _textColor),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
            child: OutlinedButton(
              onPressed: _showDiagnostics,
              style: OutlinedButton.styleFrom(
                foregroundColor: _textVariant,
                side: BorderSide(color: _outlineVariant),
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
            ? Center(child: CircularProgressIndicator(color: _tealAccent))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
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
              border: Border.all(
                  color: _outlineVariant.withValues(alpha: 0.5))),
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
              border: Border.all(
                  color: _outlineVariant.withValues(alpha: 0.5))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                          color: _textColor,
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
              Text('RETENTION POLICY',
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('30 Days (Standard Compliance)',
                        style: TextStyle(color: _textColor, fontSize: 14)),
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
              border: Border.all(
                  color: _outlineVariant.withValues(alpha: 0.5))),
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
                            decoration: BoxDecoration(
                                color: _critical,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(color: _critical, blurRadius: 4)
                                ])),
                        const SizedBox(width: 8),
                        Text('LIVE TRANSMISSION',
                            style: TextStyle(
                                color: _textColor,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildActivityChart(),
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
              ),
              const SizedBox(height: 24),
              _buildShiftCompliance(),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Container(
          decoration: BoxDecoration(
              color: _surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: _outlineVariant.withValues(alpha: 0.5))),
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
                    Text('FULL AUDIT',
                        style: TextStyle(
                            color: _tealAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5)),
                  ],
                ),
              ),
              Divider(height: 1, color: _outlineVariant),
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
            style: TextStyle(
                color: _textColor,
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
                  style: TextStyle(
                      color: _textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(color: _textVariant, fontSize: 12)),
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
              style: TextStyle(
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

  Color _shiftStatusColor(String status) {
    switch (status) {
      case 'under':
        return _critical;
      case 'over':
        return _blueAccent;
      case 'on_time':
        return _tealAccent;
      default:
        return _textVariant; // no_shift_set
    }
  }

  String _shiftStatusLabel(String status) {
    switch (status) {
      case 'under':
        return 'Under';
      case 'over':
        return 'Overtime';
      case 'on_time':
        return 'On time';
      default:
        return 'No shift set';
    }
  }

  Widget _buildShiftCompliance() {
    List<dynamic> todayRows = [];
    if (_shiftCompliance.isNotEmpty) {
      final sortedKeys = _shiftCompliance.keys.toList()..sort();
      todayRows = _shiftCompliance[sortedKeys.last] ?? [];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.schedule, 'Shift Compliance (Today)'),
        const SizedBox(height: 12),
        if (todayRows.isEmpty)
          Text('No attendance recorded today.',
              style: TextStyle(color: _textVariant, fontSize: 13))
        else
          Container(
            decoration: BoxDecoration(
              color: _surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                for (int i = 0; i < todayRows.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: i < todayRows.length - 1
                        ? BoxDecoration(
                            border: Border(
                                bottom: BorderSide(
                                    color: _outlineVariant.withValues(alpha: 0.3))))
                        : null,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(todayRows[i]['staff_name'] ?? '—',
                              style: TextStyle(color: _textColor, fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        Text(
                          todayRows[i]['expected_hours'] != null
                              ? '${todayRows[i]['actual_hours']}h / ${todayRows[i]['expected_hours']}h'
                              : '${todayRows[i]['actual_hours']}h',
                          style: TextStyle(color: _textVariant, fontSize: 12),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _shiftStatusColor(todayRows[i]['status']).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(_shiftStatusLabel(todayRows[i]['status']),
                              style: TextStyle(
                                  color: _shiftStatusColor(todayRows[i]['status']),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildActivityChart() {
    List<dynamic> todayData = [];
    if (_attendanceSummary.isNotEmpty) {
      final sortedKeys = _attendanceSummary.keys.toList()..sort();
      todayData = _attendanceSummary[sortedKeys.last] ?? [];
    }

    List<int> hourlyCounts = List.filled(10, 0);
    for (var record in todayData) {
      final entryTimeStr = record['entry_time'];
      if (entryTimeStr != null) {
        try {
          final time = DateTime.parse(entryTimeStr).toLocal();
          if (time.hour >= 8 && time.hour < 18) {
            hourlyCounts[time.hour - 8]++;
          }
        } catch (_) {}
      }
    }

    final maxCount = hourlyCounts.reduce((a, b) => a > b ? a : b);
    
    List<Widget> bars = [];
    for (int count in hourlyCounts) {
      final fill = maxCount > 0 ? (count / maxCount).toDouble() : 0.05;
      final alpha = fill.clamp(0.2, 1.0);
      final color = fill >= 0.8 ? _tealAccent : _blueAccent.withValues(alpha: alpha);
      bars.add(_bar(fill == 0 ? 0.05 : fill, color));
    }

    return Column(
      children: [
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: bars,
          ),
        ),
        const SizedBox(height: 16),
        Row(
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
            Text('18:00',
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
      return Padding(
        padding: const EdgeInsets.all(32.0),
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
          Divider(height: 1, color: _outlineVariant),
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
                    style: TextStyle(
                        color: _textVariant,
                        fontSize: 12,
                        fontFamily: 'monospace')),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(type,
                        style: TextStyle(
                            color: _textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    Text('${event['camera_name'] ?? 'System Hub'}',
                        style:
                            TextStyle(color: _textVariant, fontSize: 11)),
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
