import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../main.dart' show GlassCard, GlassBackground;
import '../network/api_routes.dart';
import '../network/network_manager.dart';

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
          final Map<String, dynamic> raw = jsonDecode(resp.body);
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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Analytics Dashboard',
          style:
              TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        backgroundColor: Colors.white.withOpacity(0.6),
        elevation: 0,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.transparent),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.black.withOpacity(0.05), height: 1.0),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.teal),
            onPressed: _fetchData,
          )
        ],
      ),
      body: GlassBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 90.0, 16.0, 16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: _buildAttendanceCard(),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: _buildEventsCard(),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildAttendanceCard() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Daily Attendance (Last 7 Days)',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _attendanceSummary.isEmpty
                ? const Center(child: Text('No attendance data.'))
                : ListView.builder(
                    itemCount: _attendanceSummary.keys.length,
                    itemBuilder: (context, index) {
                      String dateStr = _attendanceSummary.keys.elementAt(index);
                      List<dynamic> records = _attendanceSummary[dateStr]!;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        color: Colors.white.withOpacity(0.7),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.shade200)),
                        child: ExpansionTile(
                          title: Text(dateStr,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${records.length} records'),
                          children: records.map((record) {
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                backgroundColor: Colors.teal.shade50,
                                child:
                                    Text((record['staff_name'] as String)[0]),
                              ),
                              title: Text(record['staff_name']),
                              subtitle: Text(
                                  'Hours: ${record['duration_hours']} | Camera: ${record['camera_name'] ?? 'Unknown'}'),
                              trailing: Text(
                                  '${record['entry_time']?.split('T').last.substring(0, 5) ?? '?'} - ${record['exit_time']?.split('T').last.substring(0, 5) ?? 'Active'}'),
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventsCard() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent System Events',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _recentEvents.isEmpty
                ? const Center(child: Text('No recent events.'))
                : ListView.separated(
                    itemCount: _recentEvents.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final event = _recentEvents[index];
                      final type = event['event_type'];
                      final isAlert = type == 'UnknownFaceDetected' ||
                          type == 'CameraOffline' ||
                          type == 'SecurityAlert';

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(
                          isAlert
                              ? Icons.warning_amber_rounded
                              : Icons.info_outline,
                          color: isAlert ? Colors.orange : Colors.teal,
                        ),
                        title: Text(type,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text(
                          '${event['camera_name'] ?? 'System'} \n${event['timestamp']?.split('T').last.substring(0, 8) ?? ''}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
