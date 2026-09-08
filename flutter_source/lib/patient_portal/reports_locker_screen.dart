import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import '../network/api_routes.dart';
import '../network/network_manager.dart';
import 'package:intl/intl.dart';

class ReportsLockerScreen extends StatefulWidget {
  final int patientId;
  const ReportsLockerScreen({super.key, required this.patientId});

  @override
  State<ReportsLockerScreen> createState() => _ReportsLockerScreenState();
}

class _ReportsLockerScreenState extends State<ReportsLockerScreen> {
  List<dynamic> _reports = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchReports();
  }

  Future<void> _fetchReports() async {
    try {
      final response = await NetworkManager.instance.get('${ApiRoutes.baseUrl}/api/patient-portal/reports/${widget.patientId}');
      if (response.statusCode == 200) {
        setState(() {
          _reports = jsonDecode(response.body);
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // Same screen is reachable from the real, authenticated patient
          // view (/patients/:id) and the pre-auth demo (/patient-demo/:id)
          // — go() to the sibling route matching whichever parent we're
          // actually under, so the URL reflects it and permissions line up.
          // The upload screen navigates back here on its own completion,
          // which remounts fresh (no need to await a result to refresh).
          final currentPath = GoRouterState.of(context).uri.path;
          final base = currentPath.startsWith('/patient-demo')
              ? '/patient-demo'
              : '/patients';
          context.go('$base/${widget.patientId}/reports/upload');
        },
        icon: const Icon(Icons.upload_file),
        label: const Text("Upload Report"),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _reports.isEmpty
              ? const Center(child: Text("No reports uploaded yet."))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _reports.length,
                  itemBuilder: (context, index) {
                    final report = _reports[index];
                    final date = DateTime.parse(report['date']);
                    final accent = Theme.of(context).colorScheme.secondary;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: ExpansionTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.document_scanner, color: accent),
                        ),
                        title: const Text("Medical Report", style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(DateFormat.yMMMd().add_jm().format(date)),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (report['key_findings'] != null) ...[
                                  Text("Key Findings:", style: TextStyle(fontWeight: FontWeight.bold, color: accent)),
                                  const SizedBox(height: 4),
                                  Text(report['key_findings']),
                                  const Divider(height: 24),
                                ],
                                if (report['abnormalities'] != null) ...[
                                  const Text("Abnormalities:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                                  const SizedBox(height: 4),
                                  Text(report['abnormalities']),
                                  const Divider(height: 24),
                                ],
                                if (report['recommendations'] != null) ...[
                                  const Text("Recommendations:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                                  const SizedBox(height: 4),
                                  Text(report['recommendations']),
                                ],
                              ],
                            ),
                          )
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
