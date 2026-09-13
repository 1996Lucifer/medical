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
      final response = await NetworkManager.instance.get(
          '${ApiRoutes.baseUrl}/api/patient-portal/reports/${widget.patientId}');
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

  void _showReportDetail(Map<String, dynamic> report, DateTime date) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Medical Report',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: scheme.onSurface)),
              Text(DateFormat.yMMMd().add_jm().format(date),
                  style:
                      TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
              const SizedBox(height: 20),
              if (report['key_findings'] != null) ...[
                _detailSection('Key Findings', report['key_findings'],
                    scheme.secondary, scheme),
              ],
              if (report['abnormalities'] != null) ...[
                _detailSection('Abnormalities', report['abnormalities'],
                    Colors.redAccent, scheme),
              ],
              if (report['recommendations'] != null) ...[
                _detailSection('Recommendations', report['recommendations'],
                    Colors.green, scheme),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailSection(
      String label, String content, Color accent, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: accent,
                  fontSize: 12,
                  letterSpacing: 1.0)),
          const SizedBox(height: 6),
          Text(content, style: TextStyle(color: scheme.onSurface, height: 1.4)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      // Transparent, not scaffoldBackgroundColor - this screen is nested
      // inside PatientDashboardScreen's GlassBackground (it's tab content,
      // not its own top-level page), so an opaque background here would
      // paint over and hide the blurred glass backdrop.
      backgroundColor: Colors.transparent,
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
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 320,
                    mainAxisExtent: 150,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: _reports.length,
                  itemBuilder: (context, index) {
                    final report = _reports[index];
                    final date = DateTime.parse(report['date']);
                    final accent = scheme.secondary;
                    return Card(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _showReportDetail(report, date),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor:
                                        accent.withValues(alpha: 0.15),
                                    child: Icon(Icons.document_scanner,
                                        color: accent),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text('Medical Report',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                        Text(DateFormat.yMMMd().format(date),
                                            style: TextStyle(
                                                color: scheme.onSurfaceVariant,
                                                fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text('View details',
                                    style: TextStyle(
                                        color: accent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
