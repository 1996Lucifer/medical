import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../network/api_routes.dart';
import 'package:intl/intl.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class ConsultationsScreen extends StatefulWidget {
  final int patientId;
  const ConsultationsScreen({super.key, required this.patientId});

  @override
  State<ConsultationsScreen> createState() => _ConsultationsScreenState();
}

class _ConsultationsScreenState extends State<ConsultationsScreen> {
  List<dynamic> _consultations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchConsultations();
  }

  Future<void> _fetchConsultations() async {
    try {
      final response = await http.get(Uri.parse('${ApiRoutes.baseUrl}/api/patient-portal/consultations/${widget.patientId}'));
      if (response.statusCode == 200) {
        setState(() {
          _consultations = jsonDecode(response.body);
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _consultations.isEmpty
              ? const Center(child: Text("No past consultations found."))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _consultations.length,
                  itemBuilder: (context, index) {
                    final consultation = _consultations[index];
                    final date = DateTime.parse(consultation['date']);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 4,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: ExpansionTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.purple.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.history_edu, color: Colors.purple),
                        ),
                        title: const Text("Doctor Visit", style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(DateFormat.yMMMd().add_jm().format(date)),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (consultation['discharge_summary'] != null) ...[
                                  const Text("Summary:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
                                  const SizedBox(height: 8),
                                  MarkdownBody(data: consultation['discharge_summary']),
                                  const Divider(height: 24),
                                ],
                                if (consultation['prescription'] != null) ...[
                                  const Text("Prescription:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                                  const SizedBox(height: 8),
                                  MarkdownBody(data: consultation['prescription']),
                                ],
                                if (consultation['prescription'] == null)
                                  const Text("No specific prescription recorded.", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey))
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
