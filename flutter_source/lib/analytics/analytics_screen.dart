import 'dart:convert';
import 'package:flutter/material.dart';
import '../main.dart';
import '../network/api_routes.dart';
import '../network/network_manager.dart';

class AnalyticsDashboardScreen extends StatefulWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  State<AnalyticsDashboardScreen> createState() => _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState extends State<AnalyticsDashboardScreen> {
  bool _isLoading = true;
  Map<String, dynamic> _summaryData = {};
  int _selectedDays = 7;

  @override
  void initState() {
    super.initState();
    _fetchSummary();
  }

  Future<void> _fetchSummary() async {
    setState(() => _isLoading = true);
    try {
      final response = await NetworkManager.instance.get(
        ApiRoutes.attendanceSummary(_selectedDays),
      );
      if (response.statusCode == 200) {
        setState(() {
          _summaryData = jsonDecode(response.body);
        });
      }
    } catch (e) {
      debugPrint('Error fetching analytics: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
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
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Total Hours (All Staff)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
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
                    Text(total.toStringAsFixed(1), style: const TextStyle(fontSize: 10)),
                    const SizedBox(height: 4),
                    Container(
                      width: 24,
                      height: 100 * heightFactor,
                      decoration: BoxDecoration(
                        color: Colors.teal.shade400,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(shortDate, style: const TextStyle(fontSize: 10)),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Attendance Analytics',
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        backgroundColor: Colors.white.withOpacity(0.6),
        elevation: 0,
        actions: [
          DropdownButton<int>(
            value: _selectedDays,
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
            underline: const SizedBox(),
            icon: const Icon(Icons.calendar_today, size: 16),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: GlassBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _summaryData.isEmpty
                ? const Center(child: Text("No attendance data available."))
                : ListView(
                    padding: const EdgeInsets.only(top: kToolbarHeight + 40, left: 16, right: 16),
                    children: [
                      _buildGraph(),
                      const SizedBox(height: 24),
                      ...(_summaryData.keys.toList()..sort((a, b) => b.compareTo(a))).map((dateStr) {
                        List records = _summaryData[dateStr];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: GlassCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatDate(dateStr),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Divider(),
                                ...records.map((r) {
                                  return ListTile(
                                    title: Text(r['staff_name'] ?? 'Unknown'),
                                    subtitle: Text(
                                      'Camera: ${r['camera_name'] ?? 'Unknown'}\n'
                                      'Entry: ${_formatTime(r['entry_time'])}, Exit: ${_formatTime(r['exit_time'])}'
                                    ),
                                    trailing: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text('${r['duration_hours']} hrs', style: const TextStyle(fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  ),
      ),
    );
  }
}
