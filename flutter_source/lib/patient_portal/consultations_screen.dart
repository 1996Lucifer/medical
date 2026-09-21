import 'package:flutter/material.dart';
import 'dart:convert';
import '../network/api_routes.dart';
import '../network/network_manager.dart';
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchConsultations();
  }

  Future<void> _fetchConsultations() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await NetworkManager.instance.get(
          '${ApiRoutes.baseUrl}/api/patient-portal/consultations/${widget.patientId}');
      if (response.statusCode == 200) {
        setState(() {
          _consultations = jsonDecode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Could not load consultations. Please try again.';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load consultations: $e');
      setState(() {
        _error = 'Could not load consultations. Please try again.';
        _isLoading = false;
      });
    }
  }

  void _showConsultationDetail(
      Map<String, dynamic> consultation, DateTime date) {
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
              Text('Doctor Visit',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: scheme.onSurface)),
              Text(DateFormat.yMMMd().add_jm().format(date),
                  style:
                      TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
              if (consultation['staff_name'] != null) ...[
                const SizedBox(height: 4),
                Text(
                  consultation['staff_role'] != null
                      ? 'Attended by ${consultation['staff_name']} (${consultation['staff_role']})'
                      : 'Attended by ${consultation['staff_name']}',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
              ],
              const SizedBox(height: 20),
              if (consultation['discharge_summary'] != null) ...[
                Text('SUMMARY',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: scheme.secondary,
                        fontSize: 12,
                        letterSpacing: 1.0)),
                const SizedBox(height: 8),
                MarkdownBody(data: consultation['discharge_summary']),
                const SizedBox(height: 20),
              ],
              const Text('PRESCRIPTION',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                      fontSize: 12,
                      letterSpacing: 1.0)),
              const SizedBox(height: 8),
              consultation['prescription'] != null
                  ? MarkdownBody(data: consultation['prescription'])
                  : Text('No specific prescription recorded.',
                      style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.secondary;
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _fetchConsultations,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : _consultations.isEmpty
            ? const Center(child: Text("No past consultations found."))
            : GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 320,
                  mainAxisExtent: 150,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: _consultations.length,
                itemBuilder: (context, index) {
                  final consultation = _consultations[index];
                  final date = DateTime.parse(consultation['date']);
                  return Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _showConsultationDetail(consultation, date),
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
                                  child: Icon(Icons.history_edu, color: accent),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('Doctor Visit',
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
              );
  }
}
