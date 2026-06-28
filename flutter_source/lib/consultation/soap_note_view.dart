import 'package:flutter/material.dart';

class SoapNoteView extends StatelessWidget {
  final Map<String, dynamic> noteData;

  const SoapNoteView({super.key, required this.noteData});

  @override
  Widget build(BuildContext context) {
    final transcript = noteData['transcript'] ?? 'No transcript available.';
    final summary = noteData['discharge_summary'] ?? 'No summary available.';
    final patientName = noteData['patient_name'] ?? 'Unknown Patient';
    final date = noteData['date'] ?? DateTime.now().toIso8601String();

    return Card(
      margin: const EdgeInsets.all(16.0),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Patient: $patientName',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.teal),
                ),
                Text(
                  date.substring(0, 10), // just the date part
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
            const Divider(height: 32),
            const Text(
              'SOAP Note (Medical Discharge Summary)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: Text(
                summary,
                style: const TextStyle(fontSize: 15, height: 1.5),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Full Transcript',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                transcript,
                style: const TextStyle(fontSize: 14, height: 1.5, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
