import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../call/call_models.dart';
import '../call/call_service.dart';
import '../network/api_routes.dart';
import '../network/network_manager.dart';

/// Doctors this patient has actually been seen by (see
/// GET /api/patients/{id}/doctors, derived from Consultation.staff_id) -
/// the only people a patient is allowed to call, each with a quick
/// audio/video call button.
class PatientDoctorsScreen extends StatefulWidget {
  final int patientId;
  const PatientDoctorsScreen({super.key, required this.patientId});

  @override
  State<PatientDoctorsScreen> createState() => _PatientDoctorsScreenState();
}

class _PatientDoctorsScreenState extends State<PatientDoctorsScreen> {
  List<dynamic> _doctors = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchDoctors();
  }

  Future<void> _fetchDoctors() async {
    try {
      final response = await NetworkManager.instance
          .get(ApiRoutes.patientDoctors(widget.patientId));
      if (response.statusCode == 200) {
        setState(() {
          _doctors = jsonDecode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load doctors.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Network error: $e';
        _isLoading = false;
      });
    }
  }

  void _call(BuildContext context, Map<String, dynamic> doctor, CallMode mode) {
    final callService = context.read<CallService>();
    callService.startCall(
      CallPeer(userId: doctor['user_id'], name: doctor['name']),
      mode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.secondary;

    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_doctors.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            "You haven't had a consultation with a doctor yet, so there's no one to call yet.",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        mainAxisExtent: 150,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _doctors.length,
      itemBuilder: (context, index) {
        final doctor = _doctors[index];
        final canCall = doctor['can_call'] == true;
        return Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: accent.withValues(alpha: 0.15),
                      child:
                          Icon(Icons.medical_services_outlined, color: accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(doctor['name'] ?? '',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(doctor['role'] ?? 'Doctor',
                              style: TextStyle(
                                  color: scheme.onSurfaceVariant, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (canCall)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: Icon(Icons.call, color: accent, size: 20),
                        tooltip: 'Audio call',
                        onPressed: () => _call(context, doctor, CallMode.audio),
                      ),
                      IconButton(
                        icon: Icon(Icons.videocam, color: accent, size: 20),
                        tooltip: 'Video call',
                        onPressed: () => _call(context, doctor, CallMode.video),
                      ),
                    ],
                  )
                else
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text('Unavailable',
                        style: TextStyle(
                            color: scheme.onSurfaceVariant, fontSize: 11)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
