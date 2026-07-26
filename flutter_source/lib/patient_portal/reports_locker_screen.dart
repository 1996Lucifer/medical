import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../network/api_routes.dart';
import 'upload_report_screen.dart';
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
      final response = await http.get(Uri.parse('${ApiRoutes.baseUrl}/api/patient-portal/reports/${widget.patientId}'));
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => UploadReportScreen(patientId: widget.patientId)),
          );
          if (result == true) {
            setState(() => _isLoading = true);
            _fetchReports();
          }
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
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: ExpansionTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.document_scanner, color: Colors.blue),
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
                                  const Text("Key Findings:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
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
