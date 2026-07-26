import 'package:flutter/material.dart';
import '../main.dart' show GlassCard;

class ReportAnalysisView extends StatelessWidget {
  final Map<String, dynamic> reportData;

  const ReportAnalysisView({super.key, required this.reportData});

  // Aetheris Colors
  static const Color _primary = Color(0xFFffffff);
  static const Color _onSurfaceVariant = Color(0xFFbacac3);
  static const Color _primaryFixedDim = Color(0xFF38debb);
  static const Color _surfaceContainerHighest = Color(0xFF27354c);

  @override
  Widget build(BuildContext context) {
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
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _primary),
              ),
              Text(
                date.substring(0, 10), // just the date part
                style: const TextStyle(fontSize: 16, color: Colors.blueAccent),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Divider(height: 32, color: Colors.white.withValues(alpha: 0.1)),
          const Row(
            children: [
              Icon(Icons.search, color: Colors.blueAccent),
              SizedBox(width: 8),
              Text(
                'Key Findings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent),
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
              border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
            ),
            child: Text(
              keyFindings,
              style: const TextStyle(fontSize: 16, height: 1.6, color: _primary),
            ),
          ),
          const SizedBox(height: 32),
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
              SizedBox(width: 8),
              Text(
                'Identified Abnormalities',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orangeAccent),
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
              border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
            ),
            child: Text(
              abnormalities,
              style: const TextStyle(fontSize: 16, height: 1.6, color: _primary),
            ),
          ),
          const SizedBox(height: 32),
          const Row(
            children: [
              Icon(Icons.medical_services, color: _primaryFixedDim),
              SizedBox(width: 8),
              Text(
                'Clinical Recommendations',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _primaryFixedDim),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _primaryFixedDim.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _primaryFixedDim.withValues(alpha: 0.3)),
            ),
            child: Text(
              recommendations,
              style: const TextStyle(fontSize: 16, height: 1.6, color: _primary),
            ),
          ),
        ],
      ),
    );
  }
}
