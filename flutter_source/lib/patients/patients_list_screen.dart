import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../network/api_routes.dart';
import '../network/network_manager.dart';

class PatientsListScreen extends StatefulWidget {
  PatientsListScreen({super.key});

  @override
  State<PatientsListScreen> createState() => _PatientsListScreenState();
}

class _PatientsListScreenState extends State<PatientsListScreen> {
  List<dynamic> _patients = [];
  bool _isLoading = true;

  // Aetheris Colors
  Color get _bgBase => Theme.of(context).scaffoldBackgroundColor;
  Color get _primary => Theme.of(context).colorScheme.onSurface;
  Color get _onSurfaceVariant => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _primaryFixedDim => Theme.of(context).colorScheme.secondary;
  Color get _surfaceContainerLowest =>
      Theme.of(context).colorScheme.surfaceContainerLowest;

  @override
  void initState() {
    super.initState();
    _fetchPatients();
  }

  Future<void> _fetchPatients() async {
    try {
      final response = await NetworkManager.instance
          .get('${ApiRoutes.baseUrl}/api/patients');
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
          ? Center(child: CircularProgressIndicator(color: _primaryFixedDim))
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  Text(
                    'Patient Directory',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: _primary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Select a patient to view their dashboard and reports.',
                    style: TextStyle(color: _onSurfaceVariant, fontSize: 16),
                  ),
                  const SizedBox(height: 32),
                  Expanded(
                    child: _patients.isEmpty
                        ? Center(
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
                                      color:
                                          Colors.white.withValues(alpha: 0.1)),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 12),
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        _primaryFixedDim.withValues(alpha: 0.1),
                                    child: Icon(Icons.person,
                                        color: _primaryFixedDim),
                                  ),
                                  title: Text(
                                    p['name'] ?? 'Unknown',
                                    style: TextStyle(
                                        color: _primary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18),
                                  ),
                                  subtitle: Text(
                                    'MRN: ${p['mrn'] ?? 'N/A'}',
                                    style: TextStyle(color: _onSurfaceVariant),
                                  ),
                                  trailing: Icon(Icons.arrow_forward_ios,
                                      color: _primaryFixedDim, size: 16),
                                  onTap: () {
                                    final patientId = p['id'] as int;
                                    context.go('/patients/$patientId');
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
