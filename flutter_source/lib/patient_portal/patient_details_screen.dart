import 'package:flutter/material.dart';
import 'dart:convert';
import '../network/api_routes.dart';
import '../network/network_manager.dart';

class PatientDetailsScreen extends StatefulWidget {
  final int patientId;
  const PatientDetailsScreen({super.key, required this.patientId});

  @override
  State<PatientDetailsScreen> createState() => _PatientDetailsScreenState();
}

class _PatientDetailsScreenState extends State<PatientDetailsScreen> {
  bool _isLoading = true;
  String _errorMessage = "";

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _mrnCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _genderCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchPatientDetails();
  }

  Future<void> _fetchPatientDetails() async {
    try {
      final response = await NetworkManager.instance
          .get('${ApiRoutes.baseUrl}/api/patients/${widget.patientId}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _nameCtrl.text = data['name'] ?? '';
        _mrnCtrl.text = data['mrn'] ?? '';
        _dobCtrl.text = data['dob'] ?? '';
        _genderCtrl.text = data['gender'] ?? '';
      } else {
        _errorMessage = "Failed to load patient details.";
      }
    } catch (e) {
      _errorMessage = "Error connecting to server.";
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveDetails() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final response = await NetworkManager.instance.put(
        '${ApiRoutes.baseUrl}/api/patients/${widget.patientId}',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': _nameCtrl.text.trim(),
          'mrn': _mrnCtrl.text.trim(),
          'dob': _dobCtrl.text.trim(),
          'gender': _genderCtrl.text.trim(),
        }),
      );
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Profile updated successfully')));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to update profile')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error connecting to server')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage.isNotEmpty) {
      return Center(
          child:
              Text(_errorMessage, style: const TextStyle(color: Colors.red)));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Personal Information",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: "Full Name", border: OutlineInputBorder()),
              validator: (v) => v!.isEmpty ? "Name is required" : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _mrnCtrl,
              decoration: const InputDecoration(
                  labelText: "Medical Record Number (MRN)",
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _dobCtrl,
              decoration: const InputDecoration(
                  labelText: "Date of Birth (YYYY-MM-DD)",
                  border: OutlineInputBorder()),
              validator: (v) {
                if (v!.isNotEmpty) {
                  try {
                    DateTime.parse(v);
                  } catch (_) {
                    return "Invalid date format";
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _genderCtrl,
              decoration: const InputDecoration(
                  labelText: "Gender", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saveDetails,
                child: const Text("Save Changes",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
