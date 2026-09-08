import 'package:flutter/material.dart';

import '../main.dart' show GlassCard;

class ReportAnalysisView extends StatelessWidget {
  final Map<String, dynamic> reportData;

  const ReportAnalysisView({super.key, required this.reportData});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final secondary = Theme.of(context).colorScheme.secondary;
    final keyFindings = reportData['key_findings'] ?? 'No findings available.';
    final abnormalities =
        reportData['abnormalities'] ?? 'No abnormalities detected.';
    final recommendations =
        reportData['recommendations'] ?? 'No recommendations available.';
    final patientName = reportData['patient_name'] ?? 'Unknown Patient';
    final date = reportData['date'] ?? DateTime.now().toIso8601String();

    return GlassCard(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Patient: $patientName',
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold, color: onSurface),
              ),
              Text(
                date.substring(0, 10), // just the date part
                style: const TextStyle(fontSize: 16, color: Colors.blueAccent),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Divider(height: 32, color: onSurface.withValues(alpha: 0.1)),
          const Row(
            children: [
              Icon(Icons.search, color: Colors.blueAccent),
              SizedBox(width: 8),
              Text(
                'Key Findings',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
            ),
            child: Text(
              keyFindings,
              style: TextStyle(fontSize: 16, height: 1.6, color: onSurface),
            ),
          ),
          const SizedBox(height: 32),
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
              SizedBox(width: 8),
              Text(
                'Identified Abnormalities',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.orangeAccent),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
            ),
            child: Text(
              abnormalities,
              style: TextStyle(fontSize: 16, height: 1.6, color: onSurface),
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Icon(Icons.medical_services, color: secondary),
              const SizedBox(width: 8),
              Text(
                'Clinical Recommendations',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: secondary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: secondary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: secondary.withValues(alpha: 0.3)),
            ),
            child: Text(
              recommendations,
              style: TextStyle(fontSize: 16, height: 1.6, color: onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
