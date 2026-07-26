import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../main.dart' show GlassCard;

class SoapNoteView extends StatelessWidget {
  final Map<String, dynamic> noteData;
  final VoidCallback? onDelete;
  final bool isSuperAdmin;

  const SoapNoteView({super.key, required this.noteData, this.onDelete, this.isSuperAdmin = false});

  // Aetheris Colors
  static const Color _primary = Color(0xFFffffff);
  static const Color _onSurfaceVariant = Color(0xFFbacac3);
  static const Color _primaryFixedDim = Color(0xFF38debb);
  static const Color _surfaceContainerHighest = Color(0xFF27354c);

  @override
  Widget build(BuildContext context) {
    final transcript = noteData['transcript'] ?? 'No transcript available.';
    final summary = noteData['discharge_summary'] ?? 'No summary available.';
    final patientName = noteData['patient_name'] ?? 'Unknown Patient';
    final date = noteData['date'] ?? DateTime.now().toIso8601String();

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
              Row(
                children: [
                  Text(
                    date.substring(0, 10), // just the date part
                    style: const TextStyle(fontSize: 16, color: _primaryFixedDim),
                  ),
                  if (isSuperAdmin && onDelete != null) ...[
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: onDelete,
                      tooltip: 'Delete Consultation',
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Divider(height: 32, color: Colors.white.withValues(alpha: 0.1)),
          const Text(
            'SOAP Note (Medical Discharge Summary)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _primaryFixedDim),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _primaryFixedDim.withValues(alpha: 0.3)),
            ),
            child: MarkdownBody(
              data: summary,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(fontSize: 16, height: 1.6, color: _primary),
                strong: const TextStyle(fontWeight: FontWeight.bold, color: _primaryFixedDim),
                h1: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _primaryFixedDim),
                h2: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _primaryFixedDim),
                h3: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _primaryFixedDim),
                listBullet: const TextStyle(color: _primaryFixedDim),
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Full Transcript',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Text(
              transcript,
              style: const TextStyle(
                  fontSize: 14, height: 1.6, fontStyle: FontStyle.italic, color: _onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
