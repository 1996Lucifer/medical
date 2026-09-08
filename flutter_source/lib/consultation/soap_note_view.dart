import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../main.dart' show GlassCard;

class SoapNoteView extends StatelessWidget {
  final Map<String, dynamic> noteData;
  final VoidCallback? onDelete;
  final bool isSuperAdmin;

  const SoapNoteView({super.key, required this.noteData, this.onDelete, this.isSuperAdmin = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    final onSurfaceVariant = scheme.onSurfaceVariant;
    final secondary = scheme.secondary;
    final surfaceContainerHighest = scheme.surfaceContainerHighest;
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
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: onSurface),
              ),
              Row(
                children: [
                  Text(
                    date.substring(0, 10), // just the date part
                    style: TextStyle(fontSize: 16, color: secondary),
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
          Text(
            'SOAP Note (Medical Discharge Summary)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: secondary),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: secondary.withValues(alpha: 0.3)),
            ),
            child: MarkdownBody(
              data: summary,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(fontSize: 16, height: 1.6, color: onSurface),
                strong: TextStyle(fontWeight: FontWeight.bold, color: secondary),
                h1: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: secondary),
                h2: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: secondary),
                h3: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: secondary),
                listBullet: TextStyle(color: secondary),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Full Transcript',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: onSurfaceVariant),
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
              style: TextStyle(
                  fontSize: 14, height: 1.6, fontStyle: FontStyle.italic, color: onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
