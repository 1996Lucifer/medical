import 'dart:convert';
import 'package:flutter/material.dart';
import '../main.dart';
import '../camera/camera_screen.dart' show attendanceSourceBadge;
import '../network/api_routes.dart';
import '../network/network_manager.dart';

class AnalyticsDashboardScreen extends StatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  State<AnalyticsDashboardScreen> createState() =>
      _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState extends State<AnalyticsDashboardScreen> {
  bool _isLoading = true;
  Map<String, dynamic> _summaryData = {};
  Map<String, dynamic> _statsData = {};
  int _selectedDays = 7;

  // Aetheris colors
  Color get _primary => Theme.of(context).colorScheme.onSurface;
  Color get _onSurface => Theme.of(context).colorScheme.onSurface;
  Color get _onSurfaceVariant => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _primaryFixedDim => Theme.of(context).colorScheme.secondary;
  Color get _secondary => Theme.of(context).colorScheme.tertiary;
  Color get _surfaceContainerHigh =>
      Theme.of(context).colorScheme.surfaceContainerHigh;
  Color get _surfaceBright => Theme.of(context).colorScheme.surfaceBright;
  Color get _error => Theme.of(context).colorScheme.error;

  @override
  void initState() {
    super.initState();
    _fetchSummary();
  }

  Future<void> _fetchSummary() async {
    // Captured at call time - quickly flipping the day-range dropdown
    // (e.g. Today -> 30 Days) could otherwise let the slower "Today"
    // response resolve after the faster "30 Days" one and silently
    // overwrite the user's actual selection with data for a range they're
    // no longer looking at.
    final requestedDays = _selectedDays;
    setState(() => _isLoading = true);
    try {
      final response = await NetworkManager.instance.get(
        ApiRoutes.attendanceSummary(requestedDays),
      );
      if (!mounted || requestedDays != _selectedDays) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          if (data is Map<String, dynamic> && data.containsKey('summary')) {
            _summaryData = data['summary'] as Map<String, dynamic>;
            _statsData = data['stats'] as Map<String, dynamic>;
          } else {
            _summaryData = data as Map<String, dynamic>;
            _statsData = {};
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching analytics: $e');
    } finally {
      if (mounted && requestedDays == _selectedDays) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (e) {
      return dateStr;
    }
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return 'N/A';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
      final amPm = dt.hour >= 12 ? 'PM' : 'AM';
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute $amPm';
    } catch (e) {
      return 'Invalid';
    }
  }

  Widget _buildTopHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Text(
                'Staff Activity Analytics',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: _primary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 24),
              Container(
                  width: 1,
                  height: 24,
                  color: Colors.white.withValues(alpha: 0.2)),
              const SizedBox(width: 24),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedDays,
                    isDense: true,
                    icon: Icon(Icons.expand_more,
                        color: _primaryFixedDim, size: 16),
                    dropdownColor: _surfaceContainerHigh,
                    style: TextStyle(
                        color: _onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('Today')),
                      DropdownMenuItem(value: 7, child: Text('Last 7 Days')),
                      DropdownMenuItem(value: 30, child: Text('Last 30 Days')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedDays = val);
                        _fetchSummary();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    // A fixed childAspectRatio (was 2.5) has to guess the right height from
    // a width that changes with the viewport, and got it wrong - every card
    // overflowed its bottom edge by 29-45px against the ~110-120px the
    // title+value+subtitle content actually needs. An explicit height is
    // robust regardless of viewport width.
    const cardHeight = 128.0;
    final cards = [
      _buildStatCard('Active Staff', '${_statsData['active_staff'] ?? '0'}',
          'This Week', _primary),
      _buildStatCard('Avg Shift Length',
          '${_statsData['avg_shift_length'] ?? '0.0'} hrs', '', _primary),
      _buildStatCard('System Alerts', '${_statsData['system_alerts'] ?? '0'}',
          'UNRESOLVED', _error,
          isBadge: true),
      _buildStatCard('AI Utilization',
          '${_statsData['ai_utilization'] ?? '0'}%', '', _secondary,
          showProgress: true),
    ];
    final isNarrow = MediaQuery.of(context).size.width <= 900;
    Widget row(List<Widget> items) => SizedBox(
          height: cardHeight,
          child: Row(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(width: 24),
                Expanded(child: items[i]),
              ],
            ],
          ),
        );
    if (isNarrow) {
      return Column(
        children: [
          row([cards[0], cards[1]]),
          const SizedBox(height: 24),
          row([cards[2], cards[3]]),
        ],
      );
    }
    return row(cards);
  }

  Widget _buildStatCard(
      String title, String value, String subtitle, Color mainColor,
      {bool isBadge = false, bool showProgress = false}) {
    return GlassCard(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: _onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: mainColor,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      height: 1.0)),
              if (isBadge) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _error.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: _error,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ] else if (showProgress)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16.0, bottom: 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: 0.92,
                        backgroundColor: _surfaceContainerHigh,
                        valueColor: AlwaysStoppedAnimation<Color>(_secondary),
                        minHeight: 4,
                      ),
                    ),
                  ),
                )
              else if (subtitle.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                          subtitle.startsWith('+')
                              ? Icons.trending_up
                              : Icons.trending_down,
                          color: _primaryFixedDim,
                          size: 14),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: _primaryFixedDim, fontSize: 14)),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          )
        ],
      ),
    );
  }

  Widget _buildGraph() {
    if (_summaryData.isEmpty) return const SizedBox();

    Map<String, double> dailyTotals = {};
    double maxHours = 0;
    List<String> sortedKeys = _summaryData.keys.toList()..sort();

    for (var dateStr in sortedKeys) {
      double total = 0;
      for (var r in _summaryData[dateStr]) {
        total += (r['duration_hours'] ?? 0).toDouble();
      }
      dailyTotals[dateStr] = total;
      if (total > maxHours) maxHours = total;
    }

    if (maxHours == 0) maxHours = 1;

    return GlassCard(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Staff Attendance Hours",
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _primary)),
                    const SizedBox(height: 4),
                    Text("Aggregated data across all active cameras.",
                        style:
                            TextStyle(fontSize: 14, color: _onSurfaceVariant)),
                  ],
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Text('Filter: All Cameras',
                          style: TextStyle(
                              color: _onSurface,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.download_rounded,
                          color: _onSurfaceVariant, size: 20),
                    ),
                  ],
                )
              ],
            ),
            const SizedBox(height: 40),
            SizedBox(
              height: 250,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: sortedKeys.map((dateStr) {
                  double total = dailyTotals[dateStr]!;
                  double heightFactor = total / maxHours;

                  String shortDate = "";
                  try {
                    final dt = DateTime.parse(dateStr);
                    shortDate = '${dt.month}/${dt.day}';
                  } catch (_) {}

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(total.toStringAsFixed(1),
                          style: TextStyle(
                              fontSize: 11, color: _onSurfaceVariant)),
                      const SizedBox(height: 8),
                      Container(
                        width: 48,
                        height: 180 * heightFactor,
                        decoration: BoxDecoration(
                            gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  _primaryFixedDim.withValues(alpha: 0.2),
                                  _primaryFixedDim.withValues(alpha: 0.8),
                                ]),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4)),
                            boxShadow: [
                              BoxShadow(
                                color: _primaryFixedDim.withValues(alpha: 0.3),
                                blurRadius: 15,
                              )
                            ]),
                      ),
                      const SizedBox(height: 12),
                      Text(shortDate,
                          style: TextStyle(
                              fontSize: 12,
                              color: _onSurfaceVariant,
                              fontWeight: FontWeight.w600)),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ));
  }

  Widget _buildLogsTable() {
    List<Map<String, dynamic>> allRecords = [];
    final sortedKeys = _summaryData.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    for (var dateStr in sortedKeys) {
      for (var r in _summaryData[dateStr]) {
        allRecords.add({
          'date': dateStr,
          ...r,
        });
      }
    }

    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Recent Access Logs",
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _primary)),
                Row(
                  children: [
                    Container(
                      width: 240,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _surfaceBright,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Icon(Icons.search,
                              size: 16, color: _onSurfaceVariant),
                          const SizedBox(width: 8),
                          Text('Search logs...',
                              style: TextStyle(
                                  color: _onSurfaceVariant, fontSize: 13)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text('View All Logs',
                        style: TextStyle(
                            color: _primaryFixedDim,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ],
                )
              ],
            ),
          ),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: allRecords.length,
            separatorBuilder: (_, __) => Container(
                height: 1, color: Colors.white.withValues(alpha: 0.05)),
            itemBuilder: (ctx, i) {
              final r = allRecords[i];
              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24.0, vertical: 16.0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(_formatDate(r['date']),
                          style: TextStyle(
                              color: _onSurfaceVariant, fontSize: 13)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          attendanceSourceBadge(r['source'] ?? 'face',
                              size: 13),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(r['staff_name'] ?? 'Unknown',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: _primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          Icon(Icons.login, color: _primaryFixedDim, size: 16),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                                'Entry: ${_formatTime(r['entry_time'])}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: _primaryFixedDim, fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          Icon(Icons.logout, color: _secondary, size: 16),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text('Exit: ${_formatTime(r['exit_time'])}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    TextStyle(color: _secondary, fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(r['camera_name'] ?? 'Unknown Cam',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: _onSurfaceVariant, fontSize: 13)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _primaryFixedDim.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: _primaryFixedDim.withValues(alpha: 0.2)),
                      ),
                      child: Text('VERIFIED',
                          style: TextStyle(
                              color: _primaryFixedDim,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
              );
            },
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: GlassBackground(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: _primaryFixedDim))
            : _summaryData.isEmpty
                ? Center(
                    child: Text("No attendance data available.",
                        style: TextStyle(color: _onSurface)))
                : ListView(
                    padding: const EdgeInsets.all(40),
                    children: [
                      _buildTopHeader(),
                      _buildStatsGrid(),
                      const SizedBox(height: 24),
                      _buildGraph(),
                      const SizedBox(height: 24),
                      _buildLogsTable(),
                      const SizedBox(height: 40),
                    ],
                  ),
      ),
    );
  }
}
