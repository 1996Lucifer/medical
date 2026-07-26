import 'dart:convert';
import 'package:flutter/material.dart';
import '../network/api_routes.dart';
import '../network/network_manager.dart';
import '../patient_portal/patient_dashboard_screen.dart';

class PatientsListScreen extends StatefulWidget {
  const PatientsListScreen({super.key});

  @override
  State<PatientsListScreen> createState() => _PatientsListScreenState();
}

class _PatientsListScreenState extends State<PatientsListScreen> {
  List<dynamic> _patients = [];
  bool _isLoading = true;

  // Aetheris Colors
  static const Color _bgBase = Color(0xFF041329);
  static const Color _primary = Color(0xFFffffff);
  static const Color _onSurfaceVariant = Color(0xFFbacac3);
  static const Color _primaryFixedDim = Color(0xFF38debb);
  static const Color _surfaceContainerLowest = Color(0xFF010e24);

  @override
  void initState() {
    super.initState();
    _fetchPatients();
  }

  Future<void> _fetchPatients() async {
    try {
      final response = await NetworkManager.instance.get('${ApiRoutes.baseUrl}/api/patients');
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _patients = data;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgBase,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _primaryFixedDim))
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  const Text(
                    'Patient Directory',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: _primary),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Select a patient to view their dashboard and reports.',
                    style: TextStyle(color: _onSurfaceVariant, fontSize: 16),
                  ),
                  const SizedBox(height: 32),
                  Expanded(
                    child: _patients.isEmpty
                        ? const Center(
                            child: Text(
                            'No patients found.',
                            style: TextStyle(color: _onSurfaceVariant),
                          ))
                        : ListView.builder(
                            itemCount: _patients.length,
                            itemBuilder: (context, index) {
                              final p = _patients[index];
                              return Card(
                                color: _surfaceContainerLowest,
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(
                                      color: Colors.white.withValues(alpha: 0.1)),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 12),
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        _primaryFixedDim.withValues(alpha: 0.1),
                                    child: const Icon(Icons.person,
                                        color: _primaryFixedDim),
                                  ),
                                  title: Text(
                                    p['name'] ?? 'Unknown',
                                    style: const TextStyle(
                                        color: _primary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18),
                                  ),
                                  subtitle: Text(
                                    'MRN: ${p['mrn'] ?? 'N/A'}',
                                    style: const TextStyle(
                                        color: _onSurfaceVariant),
                                  ),
                                  trailing: const Icon(Icons.arrow_forward_ios,
                                      color: _primaryFixedDim, size: 16),
                                  onTap: () {
                                    final patientId = p['id'] as int;
                                    Navigator.of(context).push(MaterialPageRoute(
                                        builder: (_) => PatientDashboardScreen(
                                            patientId: patientId)));
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
