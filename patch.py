import re

with open("flutter_source/lib/consultation/consultation_screen.dart", "r") as f:
    content = f.read()

# 1. Imports
imports = """import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui';
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';"""

content = re.sub(r"import 'dart:convert';.*?import 'package:record/record\.dart';", imports, content, flags=re.DOTALL)


# 2. State variables
state_vars = """
  bool _isProcessing = false;
  bool _isTranscribing = false;
  
  String? _recordedAudioPath;
  String? _transcriptionText;
  
  Timer? _recordTimer;
  int _recordDuration = 0;
  
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  final TextEditingController _transcriptController = TextEditingController();
"""

content = re.sub(r"  bool _isProcessing = false;", state_vars.strip(), content)

# 3. Init State
init_state_new = """  @override
  void initState() {
    super.initState();
    _loadSavedNotes();
    _fetchPatients();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    });
  }"""
content = re.sub(r"  @override\s+void initState\(\) \{.*?\.\.repeat\(reverse: true\);\s+\}", init_state_new, content, flags=re.DOTALL)

# 4. Dispose
dispose_new = """  @override
  void dispose() {
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _recordTimer?.cancel();
    _transcriptController.dispose();
    if (_ownsPatientNameController) {
      _patientNameController.dispose();
    }
    _pulseController.dispose();
    super.dispose();
  }"""
content = re.sub(r"  @override\s+void dispose\(\) \{.*?\n  \}", dispose_new, content, flags=re.DOTALL)

# 5. Functions: _startRecording, _stopRecordingAndProcess, _uploadAudioForAnalysis -> _startRecording, _stopRecording, _transcribe, _generate, etc.
# Find the start of _startRecording
start_rec_idx = content.find("  Future<void> _startRecording() async {")
end_rec_idx = content.find("  Future<void> _showFileOptionsAndAnalyze() async {")

new_funcs = """  String _formatDuration(int seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _startRecording() async {
    if (_patientNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter patient name first')),
      );
      return;
    }

    try {
      if (await _audioRecorder.hasPermission()) {
        String? path;
        if (!kIsWeb) {
          final dir = await getApplicationDocumentsDirectory();
          path = '${dir.path}/consultation_${DateTime.now().millisecondsSinceEpoch}.m4a';
        }
        await _audioRecorder.start(const RecordConfig(), path: path ?? '');

        setState(() {
          _isRecording = true;
          _currentNote = null;
          _currentReport = null;
          _recordedAudioPath = null;
          _transcriptionText = null;
          _recordDuration = 0;
        });

        _recordTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
          setState(() {
            _recordDuration++;
          });
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error starting recording: $e')),
      );
    }
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    try {
      final pathOrUrl = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        if (pathOrUrl != null) {
          _recordedAudioPath = pathOrUrl;
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error stopping recording: $e')),
      );
    }
  }
  
  void _discardAudio() {
    setState(() {
      _recordedAudioPath = null;
      _transcriptionText = null;
      _recordDuration = 0;
    });
  }

  Future<void> _playAudio() async {
    if (_recordedAudioPath == null) return;
    if (_isPlaying) {
      await _audioPlayer.pause();
      setState(() => _isPlaying = false);
    } else {
      await _audioPlayer.play(kIsWeb ? UrlSource(_recordedAudioPath!) : DeviceFileSource(_recordedAudioPath!));
      setState(() => _isPlaying = true);
    }
  }

  Future<void> _transcribeAudio() async {
    if (_recordedAudioPath == null) return;
    setState(() => _isTranscribing = true);
    try {
      final request = NetworkManager.instance.multipartRequest('POST', '${ApiRoutes.baseUrl}/api/transcribe');
      if (kIsWeb) {
        final response = await http.get(Uri.parse(_recordedAudioPath!));
        request.files.add(http.MultipartFile.fromBytes('file', response.bodyBytes, filename: 'audio.webm'));
      } else {
        request.files.add(await http.MultipartFile.fromPath('file', _recordedAudioPath!));
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _transcriptionText = data['transcript'];
          _transcriptController.text = _transcriptionText ?? '';
          _isTranscribing = false;
        });
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _isTranscribing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Transcription failed: $e')));
    }
  }

  Future<void> _generateSummary() async {
    if (_transcriptController.text.trim().isEmpty) return;
    setState(() => _isProcessing = true);
    try {
      final response = await NetworkManager.instance.post(
        '${ApiRoutes.baseUrl}/api/consultations/generate',
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'patient_name': _patientNameController.text.trim(),
          'transcript': _transcriptController.text.trim(),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await SecureStorageService.instance.savePatientNote(_patientNameController.text.trim(), data);
        _loadSavedNotes();
        _openDrawerWithNote(data);
        _patientNameController.clear();
        setState(() {
          _recordedAudioPath = null;
          _transcriptionText = null;
          _recordDuration = 0;
        });
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AI Processing failed: $e')));
    } finally {
      setState(() => _isProcessing = false);
    }
  }

"""

content = content[:start_rec_idx] + new_funcs + content[end_rec_idx:]


# 6. UI Replacement
ui_target = """                              if (_isProcessing)
                                Column(
                                  children: [
                                    const CircularProgressIndicator(
                                        color: _primaryFixedDim,
                                        strokeWidth: 3),
                                    const SizedBox(height: 20),
                                    FadeTransition(
                                      opacity: _pulseController,
                                      child: const Text(
                                          'Processing with Aegis AI...',
                                          style: TextStyle(
                                              color: _primaryFixedDim,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                )
                              else
                                Column(
                                  children: [
                                    GestureDetector(
                                      onTap: _isRecording
                                          ? _stopRecordingAndProcess
                                          : _startRecording,
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 300),
                                        width: 90,
                                        height: 90,
                                        decoration: BoxDecoration(
                                          color: _isRecording
                                              ? Colors.redAccent
                                                  .withValues(alpha: 0.2)
                                              : _primaryFixedDim.withValues(
                                                  alpha: 0.1),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: _isRecording
                                                ? Colors.redAccent
                                                : _primaryFixedDim,
                                            width: 2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: (_isRecording
                                                      ? Colors.redAccent
                                                      : _primaryFixedDim)
                                                  .withValues(alpha: 0.3),
                                              blurRadius:
                                                  _isRecording ? 30 : 20,
                                              spreadRadius:
                                                  _isRecording ? 10 : 0,
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                            _isRecording
                                                ? Icons.stop_rounded
                                                : Icons.mic_rounded,
                                            color: _isRecording
                                                ? Colors.redAccent
                                                : _primaryFixedDim,
                                            size: 40),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                        _isRecording
                                            ? 'Recording...'
                                            : 'Record Audio',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: _isRecording
                                                ? Colors.redAccent
                                                : _onSurfaceVariant)),
                                    const SizedBox(height: 40),
                                    ElevatedButton.icon(
                                      onPressed: _isRecording
                                          ? null
                                          : _showFileOptionsAndAnalyze,
                                      icon: const Icon(
                                          Icons.document_scanner_rounded,
                                          size: 20),
                                      label: const Text('Analyze Report (Image/PDF)',
                                          style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            _surfaceContainerLowest,
                                        foregroundColor: _primary,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 24, vertical: 16),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16)),
                                        side: BorderSide(
                                            color: Colors.white
                                                .withValues(alpha: 0.2)),
                                      ),
                                    ),
                                  ],
                                ),"""

ui_replacement = """                              if (_isProcessing)
                                Column(
                                  children: [
                                    const CircularProgressIndicator(
                                        color: _primaryFixedDim,
                                        strokeWidth: 3),
                                    const SizedBox(height: 20),
                                    FadeTransition(
                                      opacity: _pulseController,
                                      child: const Text(
                                          'Processing with Aegis AI...',
                                          style: TextStyle(
                                              color: _primaryFixedDim,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                )
                              else if (_isTranscribing)
                                Column(
                                  children: [
                                    const CircularProgressIndicator(
                                        color: _primaryFixedDim,
                                        strokeWidth: 3),
                                    const SizedBox(height: 20),
                                    FadeTransition(
                                      opacity: _pulseController,
                                      child: const Text(
                                          'Transcribing Audio...',
                                          style: TextStyle(
                                              color: _primaryFixedDim,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                )
                              else if (_transcriptionText != null)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const Text('Edit Transcript',
                                        style: TextStyle(
                                            color: _primary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16)),
                                    const SizedBox(height: 8),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: _surfaceContainerLowest.withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                                      ),
                                      child: TextField(
                                        controller: _transcriptController,
                                        maxLines: 8,
                                        style: const TextStyle(color: Colors.white, fontSize: 14),
                                        decoration: const InputDecoration(
                                            border: InputBorder.none,
                                            contentPadding: EdgeInsets.all(16)),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: [
                                        TextButton.icon(
                                          onPressed: _discardAudio,
                                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                          label: const Text('Discard', style: TextStyle(color: Colors.redAccent)),
                                        ),
                                        ElevatedButton.icon(
                                          onPressed: _generateSummary,
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor: _primaryFixedDim,
                                              foregroundColor: Colors.black,
                                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                                          icon: const Icon(Icons.auto_awesome),
                                          label: const Text('Generate Summary',
                                              style: TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  ],
                                )
                              else if (_recordedAudioPath != null)
                                Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: _surfaceContainerLowest,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          IconButton(
                                            icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                                                color: _primaryFixedDim, size: 40),
                                            onPressed: _playAudio,
                                          ),
                                          const SizedBox(width: 16),
                                          Text('Audio Recorded (${_formatDuration(_recordDuration)})',
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: [
                                        TextButton.icon(
                                          onPressed: _discardAudio,
                                          icon: const Icon(Icons.replay, color: _onSurfaceVariant),
                                          label: const Text('Retake', style: TextStyle(color: _onSurfaceVariant)),
                                        ),
                                        ElevatedButton.icon(
                                          onPressed: _transcribeAudio,
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor: _primaryFixedDim,
                                              foregroundColor: Colors.black,
                                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                                          icon: const Icon(Icons.text_fields),
                                          label: const Text('Transcribe',
                                              style: TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  ],
                                )
                              else
                                Column(
                                  children: [
                                    GestureDetector(
                                      onTap: _isRecording
                                          ? _stopRecording
                                          : _startRecording,
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 300),
                                        width: 90,
                                        height: 90,
                                        decoration: BoxDecoration(
                                          color: _isRecording
                                              ? Colors.redAccent
                                                  .withValues(alpha: 0.2)
                                              : _primaryFixedDim.withValues(
                                                  alpha: 0.1),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: _isRecording
                                                ? Colors.redAccent
                                                : _primaryFixedDim,
                                            width: 2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: (_isRecording
                                                      ? Colors.redAccent
                                                      : _primaryFixedDim)
                                                  .withValues(alpha: 0.3),
                                              blurRadius:
                                                  _isRecording ? 30 : 20,
                                              spreadRadius:
                                                  _isRecording ? 10 : 0,
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                            _isRecording
                                                ? Icons.stop_rounded
                                                : Icons.mic_rounded,
                                            color: _isRecording
                                                ? Colors.redAccent
                                                : _primaryFixedDim,
                                            size: 40),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                        _isRecording
                                            ? 'Recording... ${_formatDuration(_recordDuration)}'
                                            : 'Record Audio',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: _isRecording
                                                ? Colors.redAccent
                                                : _onSurfaceVariant)),
                                    const SizedBox(height: 40),
                                    ElevatedButton.icon(
                                      onPressed: _isRecording
                                          ? null
                                          : _showFileOptionsAndAnalyze,
                                      icon: const Icon(
                                          Icons.document_scanner_rounded,
                                          size: 20),
                                      label: const Text('Analyze Report (Image/PDF)',
                                          style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            _surfaceContainerLowest,
                                        foregroundColor: _primary,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 24, vertical: 16),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16)),
                                        side: BorderSide(
                                            color: Colors.white
                                                .withValues(alpha: 0.2)),
                                      ),
                                    ),
                                  ],
                                ),"""

content = content.replace(ui_target, ui_replacement)

with open("flutter_source/lib/consultation/consultation_screen.dart", "w") as f:
    f.write(content)
