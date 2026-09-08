import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:frontend/providers/site_config_provider.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../main.dart' show GlassBackground, GlassCard;
import '../network/api_routes.dart';
import '../network/network_manager.dart';
import '../providers/auth_provider.dart';
import '../storage/secure_storage_service.dart';
import 'report_analysis_view.dart';
import 'soap_note_view.dart';

class ConsultationScreen extends StatefulWidget {
  ConsultationScreen({super.key});

  @override
  State<ConsultationScreen> createState() => _ConsultationScreenState();
}

class _ConsultationScreenState extends State<ConsultationScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AudioRecorder _audioRecorder = AudioRecorder();
  TextEditingController _patientNameController = TextEditingController();
  bool _ownsPatientNameController = true;

  final ImagePicker _imagePicker = ImagePicker();

  bool _isRecording = false;
  bool _isProcessing = false;
  bool _isTranscribing = false;

  String? _recordedAudioPath;
  String? _transcriptionText;

  Uint8List? _uploadedAudioBytes;
  String? _uploadedAudioFilename;

  Timer? _recordTimer;
  int _recordDuration = 0;

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  final TextEditingController _transcriptController = TextEditingController();

  Map<String, dynamic>? _currentNote;
  Map<String, dynamic>? _currentReport;

  List<Map<String, dynamic>> _savedNotes = [];
  List<String> _availablePatients = [];

  // Aetheris Colors
  Color get _primary => Theme.of(context).colorScheme.onSurface;
  Color get _onSurfaceVariant => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _primaryFixedDim => Theme.of(context).colorScheme.secondary;
  Color get _surfaceContainerHighest =>
      Theme.of(context).colorScheme.surfaceContainerHighest;
  Color get _surfaceContainerLowest =>
      Theme.of(context).colorScheme.surfaceContainerLowest;

  late AnimationController _pulseController;

  @override
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
  }

  @override
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
  }

  Future<void> _fetchPatients() async {
    try {
      final response = await NetworkManager.instance
          .get('${ApiRoutes.baseUrl}/api/patients');
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _availablePatients = data.map((e) => e['name'].toString()).toList();
        });
      }
    } catch (e) {
      debugPrint("Failed to fetch patients: $e");
    }
  }

  Future<void> _loadSavedNotes() async {
    final notes = await SecureStorageService.instance.getAllPatientNotes();
    setState(() {
      _savedNotes = notes;
    });
  }

  void _openDrawerWithNote(Map<String, dynamic> note) {
    setState(() {
      _currentNote = note;
      _currentReport = null;
    });
    _scaffoldKey.currentState?.openEndDrawer();
  }

  void _openDrawerWithReport(Map<String, dynamic> report) {
    setState(() {
      _currentReport = report;
      _currentNote = null;
    });
    _scaffoldKey.currentState?.openEndDrawer();
  }

  String _formatDuration(int seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _startRecording() async {
    if (_patientNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: const Text('Please enter patient name first')),
      );
      return;
    }

    try {
      if (await _audioRecorder.hasPermission()) {
        String? path;
        if (!kIsWeb) {
          final dir = await getApplicationDocumentsDirectory();
          path =
              '${dir.path}/consultation_${DateTime.now().millisecondsSinceEpoch}.m4a';
        }
        await _audioRecorder.start(const RecordConfig(), path: path ?? '');

        setState(() {
          _isRecording = true;
          _currentNote = null;
          _currentReport = null;
          _recordedAudioPath = null;
          _uploadedAudioBytes = null;
          _uploadedAudioFilename = null;
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

  Future<void> _uploadAudioFile() async {
    if (_patientNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: const Text('Please enter patient name first')),
      );
      return;
    }

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['m4a', 'mp3', 'wav', 'aac', 'ogg', 'flac'],
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      setState(() {
        if (kIsWeb) {
          _uploadedAudioBytes = file.bytes;
          _uploadedAudioFilename = file.name;
          _recordedAudioPath = null;
        } else {
          _recordedAudioPath = file.path;
          _uploadedAudioBytes = null;
          _uploadedAudioFilename = null;
        }
        _recordDuration = 0;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading audio: $e')),
      );
    }
  }

  void _discardAudio() {
    setState(() {
      _recordedAudioPath = null;
      _uploadedAudioBytes = null;
      _uploadedAudioFilename = null;
      _transcriptionText = null;
      _recordDuration = 0;
    });
  }

  Future<void> _playAudio() async {
    if (_recordedAudioPath == null && _uploadedAudioBytes == null) return;
    if (_isPlaying) {
      await _audioPlayer.pause();
      setState(() => _isPlaying = false);
    } else {
      if (kIsWeb && _uploadedAudioBytes != null) {
        await _audioPlayer.play(BytesSource(_uploadedAudioBytes!));
      } else if (_recordedAudioPath != null) {
        await _audioPlayer.play(kIsWeb
            ? UrlSource(_recordedAudioPath!)
            : DeviceFileSource(_recordedAudioPath!));
      }
      setState(() => _isPlaying = true);
    }
  }

  Future<void> _transcribeAudio() async {
    if (_recordedAudioPath == null && _uploadedAudioBytes == null) return;
    setState(() => _isTranscribing = true);
    try {
      final request = NetworkManager.instance
          .multipartRequest('POST', '${ApiRoutes.baseUrl}/api/transcribe');
      if (kIsWeb && _uploadedAudioBytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
            'file', _uploadedAudioBytes!,
            filename: _uploadedAudioFilename ?? 'audio.webm'));
      } else if (kIsWeb && _recordedAudioPath != null) {
        final response = await http.get(Uri.parse(_recordedAudioPath!));
        request.files.add(http.MultipartFile.fromBytes(
            'file', response.bodyBytes,
            filename: 'audio.webm'));
      } else if (_recordedAudioPath != null) {
        request.files.add(
            await http.MultipartFile.fromPath('file', _recordedAudioPath!));
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Transcription failed: $e')));
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
        await SecureStorageService.instance
            .savePatientNote(_patientNameController.text.trim(), data);
        _loadSavedNotes();
        _openDrawerWithNote(data);
        _patientNameController.clear();
        setState(() {
          _recordedAudioPath = null;
          _uploadedAudioBytes = null;
          _uploadedAudioFilename = null;
          _transcriptionText = null;
          _recordDuration = 0;
        });
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('AI Processing failed: $e')));
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _deleteConsultation(
      int? consultationId, String patientName) async {
    if (consultationId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surfaceContainerHighest,
        title: Text('Delete Consultation',
            style: TextStyle(color: _primary)),
        content: Text(
            'Are you sure you want to delete this consultation? This action cannot be undone.',
            style: TextStyle(color: _onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: _onSurfaceVariant)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text('Delete',
                style: TextStyle(color: _primary)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await NetworkManager.instance.delete(
        '${ApiRoutes.baseUrl}/api/consultations/$consultationId',
      );
      if (response.statusCode == 200) {
        await SecureStorageService.instance.deleteNoteById(consultationId);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: const Text('Consultation deleted')));
        _loadSavedNotes();
        if (_currentNote != null && _currentNote!['id'] == consultationId) {
          setState(() => _currentNote = null);
        }
        _scaffoldKey.currentState?.closeEndDrawer();
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
    }
  }

  Future<void> _showFileOptionsAndAnalyze() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surfaceContainerHighest,
      shape: const RoundedRectangleBorder(
        borderRadius:
            const BorderRadius.vertical(top: const Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt, color: _primary),
                title: Text('Take Photo',
                    style: TextStyle(color: _primary)),
                onTap: () {
                  Navigator.pop(context);
                  _processPickedFile(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Icon(Icons.folder, color: _primary),
                title: Text('Choose File (Image/PDF)',
                    style: TextStyle(color: _primary)),
                onTap: () {
                  Navigator.pop(context);
                  _processPickedFile(null);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _processPickedFile(ImageSource? source) async {
    try {
      Uint8List? fileBytes;
      String? fileName;

      if (source != null) {
        final XFile? image = await _imagePicker.pickImage(source: source);
        if (image == null) return;
        fileBytes = await image.readAsBytes();
        fileName = image.name;
      } else {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
          withData: true,
        );
        if (result == null || result.files.isEmpty) return;
        fileBytes = result.files.first.bytes;
        fileName = result.files.first.name;

        if (fileBytes == null && result.files.first.path != null) {
          fileBytes = await io.File(result.files.first.path!).readAsBytes();
        }
      }

      if (fileBytes == null) return;

      setState(() {
        _isProcessing = true;
      });

      final request = NetworkManager.instance
          .multipartRequest('POST', '${ApiRoutes.baseUrl}/api/analysis/report');

      if (_patientNameController.text.trim().isNotEmpty) {
        request.fields['patient_name'] = _patientNameController.text.trim();
      }

      request.files.add(http.MultipartFile.fromBytes('file', fileBytes,
          filename: fileName ?? 'file'));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);

        bool requiresName = responseData['requires_name'] ?? false;
        Map<String, dynamic> reportData = responseData['data'] ?? responseData;

        if (requiresName) {
          final String? enteredName = await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              final TextEditingController nameController =
                  TextEditingController();
              return AlertDialog(
                backgroundColor: _surfaceContainerHighest,
                title: Text('Patient Name Required',
                    style: TextStyle(color: _primary)),
                content: TextField(
                  controller: nameController,
                  style: TextStyle(color: _primary),
                  decoration: InputDecoration(
                      hintText: "Enter Patient Name",
                      hintStyle: TextStyle(color: _onSurfaceVariant.withValues(alpha: 0.6)),
                      helperText:
                          "The AI could not confidently extract the name from the image.",
                      helperStyle: TextStyle(color: _onSurfaceVariant.withValues(alpha: 0.4))),
                  autofocus: true,
                ),
                actions: <Widget>[
                  TextButton(
                    child: Text('Cancel',
                        style: TextStyle(color: _onSurfaceVariant)),
                    onPressed: () {
                      Navigator.of(context).pop(null);
                    },
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryFixedDim),
                    child: const Text('Save',
                        style: const TextStyle(color: Colors.black)),
                    onPressed: () {
                      if (nameController.text.trim().isNotEmpty) {
                        Navigator.of(context).pop(nameController.text.trim());
                      }
                    },
                  ),
                ],
              );
            },
          );

          if (enteredName == null) {
            return;
          }

          reportData['patient_name'] = enteredName;
          final saveResponse = await NetworkManager.instance.post(
            '${ApiRoutes.baseUrl}/api/analysis/save_report',
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(reportData),
          );

          if (saveResponse.statusCode == 200) {
            final savedData = jsonDecode(saveResponse.body);
            reportData = savedData;
            _patientNameController.text = enteredName;
          } else {
            throw Exception('Failed to save report: ${saveResponse.body}');
          }
        } else {
          _patientNameController.text = reportData['patient_name'] ?? '';
        }

        final finalName = reportData['patient_name'] ?? 'Unknown';
        await SecureStorageService.instance
            .savePatientNote(finalName, reportData);
        _loadSavedNotes();
        _openDrawerWithReport(reportData);
        _patientNameController.clear();
      } else {
        throw Exception(
            'Server error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image Analysis failed: $e')),
      );
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Widget _buildPatientCard(Map<String, dynamic> note, bool isReport) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        if (isReport) {
          _openDrawerWithReport(note);
        } else {
          _openDrawerWithNote(note);
        }
      },
      child: GlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isReport
                        ? Colors.blueAccent.withValues(alpha: 0.1)
                        : _primaryFixedDim.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: isReport
                            ? Colors.blueAccent.withValues(alpha: 0.3)
                            : _primaryFixedDim.withValues(alpha: 0.3)),
                  ),
                  child: Icon(isReport ? Icons.analytics : Icons.description,
                      color: isReport ? Colors.blueAccent : _primaryFixedDim,
                      size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    note['patient_name'] ?? 'Unknown Patient',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: _primary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (Provider.of<AuthProvider>(context, listen: false).role ==
                        'superadmin' &&
                    !isReport)
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.redAccent),
                    tooltip: 'Delete Consultation',
                    onPressed: () => _deleteConsultation(
                        note['id'], note['patient_name'] ?? ''),
                  ),
              ],
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(note['date']?.substring(0, 10) ?? '',
                    style: TextStyle(
                        color: _onSurfaceVariant, fontWeight: FontWeight.w600)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: isReport
                          ? Colors.blueAccent.withValues(alpha: 0.2)
                          : _primaryFixedDim.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(isReport ? 'AI Report' : 'SOAP Note',
                      style: TextStyle(
                          color:
                              isReport ? Colors.blueAccent : _primaryFixedDim,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                )
              ],
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final siteConfig = context.watch<SiteConfigProvider>();
    return Scaffold(
      key: _scaffoldKey,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Medical Consultation',
          style:
              TextStyle(fontWeight: FontWeight.bold, color: _primary),
        ),
        backgroundColor: _surfaceContainerLowest.withValues(alpha: 0.3),
        elevation: 0,
        actions: [
          const SizedBox.shrink(),
        ],
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.transparent),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
              color: _primary.withValues(alpha: 0.05), height: 1.0),
        ),
      ),
      endDrawer: Drawer(
        width: MediaQuery.of(context).size.width > 800
            ? 600
            : MediaQuery.of(context).size.width * 0.85,
        backgroundColor: _surfaceContainerLowest.withValues(alpha: 0.95),
        elevation: 24,
        shape: const RoundedRectangleBorder(
            borderRadius:
                const BorderRadius.horizontal(left: const Radius.circular(32))),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Patient Record',
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: _primary)),
                    Container(
                      decoration: BoxDecoration(
                          color: _primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle),
                      child: IconButton(
                        icon: Icon(Icons.close_rounded,
                            color: _primary),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    )
                  ],
                ),
              ),
              Divider(
                  height: 1,
                  thickness: 1,
                  color: _primary.withValues(alpha: 0.1)),
              if (_currentNote != null)
                Expanded(
                    child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: SoapNoteView(
                          noteData: _currentNote!,
                          isSuperAdmin:
                              Provider.of<AuthProvider>(context, listen: false)
                                      .role ==
                                  'superadmin',
                          onDelete: () => _deleteConsultation(
                              _currentNote!['id'],
                              _currentNote!['patient_name'] ?? ''),
                        )))
              else if (_currentReport != null)
                Expanded(
                    child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child:
                            ReportAnalysisView(reportData: _currentReport!))),
            ],
          ),
        ),
      ),
      body: GlassBackground(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Column(
                children: [
                  const SizedBox(height: 100),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isDesktop = constraints.maxWidth > 800;

                        final leftTile = GlassCard(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Record Consultation\n& Analyze Reports',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    color: _primary),
                              ),
                              const SizedBox(height: 32),
                              Autocomplete<String>(
                                optionsBuilder:
                                    (TextEditingValue textEditingValue) {
                                  if (textEditingValue.text.isEmpty) {
                                    return const Iterable<String>.empty();
                                  }
                                  return _availablePatients
                                      .where((String option) {
                                    return option.toLowerCase().contains(
                                        textEditingValue.text.toLowerCase());
                                  });
                                },
                                onSelected: (String selection) {
                                  _patientNameController.text = selection;
                                },
                                optionsViewBuilder:
                                    (context, onSelected, options) {
                                  return Align(
                                    alignment: Alignment.topLeft,
                                    child: Material(
                                      elevation: 8,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16)),
                                      color: _surfaceContainerHighest,
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                            maxHeight: 250, maxWidth: 350),
                                        child: ListView.builder(
                                          padding: EdgeInsets.zero,
                                          shrinkWrap: true,
                                          itemCount: options.length,
                                          itemBuilder: (context, index) {
                                            final option =
                                                options.elementAt(index);
                                            return InkWell(
                                              onTap: () => onSelected(option),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 24,
                                                        vertical: 16),
                                                child: Text(option,
                                                    style: TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: _primary)),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                fieldViewBuilder: (context, controller,
                                    focusNode, onFieldSubmitted) {
                                  if (_patientNameController != controller) {
                                    if (_ownsPatientNameController) {
                                      _patientNameController.dispose();
                                      _ownsPatientNameController = false;
                                    }
                                    _patientNameController = controller;
                                    _patientNameController.addListener(() {
                                      setState(() {});
                                    });
                                  }
                                  return Container(
                                    decoration: BoxDecoration(
                                      color: _surfaceContainerLowest.withValues(
                                          alpha: 0.5),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                          color: _primary
                                              .withValues(alpha: 0.1)),
                                    ),
                                    child: TextField(
                                      controller: controller,
                                      focusNode: focusNode,
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w500,
                                          color: _primary),
                                      decoration: InputDecoration(
                                          labelText:
                                              'Patient Name (Search or Create New)',
                                          labelStyle: TextStyle(
                                              color: _onSurfaceVariant),
                                          border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              borderSide: BorderSide.none),
                                          prefixIcon: Icon(
                                              Icons.person_search_rounded,
                                              color: _primaryFixedDim),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 24,
                                                  vertical: 16)),
                                      enabled: !_isRecording && !_isProcessing,
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 40),
                              if (_isProcessing)
                                Column(
                                  children: [
                                    CircularProgressIndicator(
                                        color: _primaryFixedDim,
                                        strokeWidth: 3),
                                    const SizedBox(height: 20),
                                    FadeTransition(
                                      opacity: _pulseController,
                                      child: Text(
                                          'Processing with ${siteConfig.agentName}...',
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
                                    CircularProgressIndicator(
                                        color: _primaryFixedDim,
                                        strokeWidth: 3),
                                    const SizedBox(height: 20),
                                    FadeTransition(
                                      opacity: _pulseController,
                                      child: Text('Transcribing Audio...',
                                          style: TextStyle(
                                              color: _primaryFixedDim,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                )
                              else if (_transcriptionText != null)
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text('Edit Transcript',
                                        style: TextStyle(
                                            color: _primary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16)),
                                    const SizedBox(height: 8),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: _surfaceContainerLowest
                                            .withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: _primary
                                                .withValues(alpha: 0.1)),
                                      ),
                                      child: TextField(
                                        controller: _transcriptController,
                                        maxLines: 8,
                                        style: TextStyle(
                                            color: _primary, fontSize: 14),
                                        decoration: const InputDecoration(
                                            border: InputBorder.none,
                                            contentPadding:
                                                const EdgeInsets.all(16)),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: [
                                        TextButton.icon(
                                          onPressed: _discardAudio,
                                          icon: const Icon(Icons.delete_outline,
                                              color: Colors.redAccent),
                                          label: const Text('Discard',
                                              style: const TextStyle(
                                                  color: Colors.redAccent)),
                                        ),
                                        ElevatedButton.icon(
                                          onPressed: _generateSummary,
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor: _primaryFixedDim,
                                              foregroundColor: Colors.black,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 24,
                                                      vertical: 12)),
                                          icon: const Icon(Icons.auto_awesome),
                                          label: const Text('Generate Summary',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  ],
                                )
                              else if (_recordedAudioPath != null ||
                                  _uploadedAudioBytes != null)
                                Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: _surfaceContainerLowest,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          IconButton(
                                            icon: Icon(
                                                _isPlaying
                                                    ? Icons.pause_circle_filled
                                                    : Icons.play_circle_fill,
                                                color: _primaryFixedDim,
                                                size: 40),
                                            onPressed: _playAudio,
                                          ),
                                          const SizedBox(width: 16),
                                          Text(
                                              'Audio Recorded (${_formatDuration(_recordDuration)})',
                                              style: TextStyle(
                                                  color: _primary,
                                                  fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: [
                                        TextButton.icon(
                                          onPressed: _discardAudio,
                                          icon: const Icon(Icons.delete_outline,
                                              color: Colors.redAccent),
                                          label: const Text('Discard',
                                              style: const TextStyle(
                                                  color: Colors.redAccent)),
                                        ),
                                        TextButton.icon(
                                          onPressed: _discardAudio,
                                          icon: Icon(Icons.replay,
                                              color: _onSurfaceVariant),
                                          label: Text('Retake',
                                              style: TextStyle(
                                                  color: _onSurfaceVariant)),
                                        ),
                                        ElevatedButton.icon(
                                          onPressed: _transcribeAudio,
                                          style: ElevatedButton.styleFrom(
                                              backgroundColor: _primaryFixedDim,
                                              foregroundColor: Colors.black,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 24,
                                                      vertical: 12)),
                                          icon: const Icon(Icons.text_fields),
                                          label: const Text('Transcribe',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold)),
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
                                    if (!_isRecording) ...[
                                      const SizedBox(height: 8),
                                      TextButton.icon(
                                        onPressed: _uploadAudioFile,
                                        icon: Icon(Icons.upload_file,
                                            color: _primaryFixedDim, size: 20),
                                        label: Text('Upload Audio File',
                                            style: TextStyle(
                                                color: _primaryFixedDim)),
                                      ),
                                    ],
                                    const SizedBox(height: 32),
                                    ElevatedButton.icon(
                                      onPressed: _isRecording
                                          ? null
                                          : _showFileOptionsAndAnalyze,
                                      icon: const Icon(
                                          Icons.document_scanner_rounded,
                                          size: 20),
                                      label: const Text(
                                          'Analyze Report (Image/PDF)',
                                          style: const TextStyle(
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
                                            color: _primary
                                                .withValues(alpha: 0.2)),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        );

                        final searchQuery =
                            _patientNameController.text.trim().toLowerCase();
                        final filteredNotes = searchQuery.isEmpty
                            ? _savedNotes
                            : _savedNotes.where((note) {
                                final name =
                                    (note['patient_name'] as String? ?? '')
                                        .toLowerCase();
                                return name.contains(searchQuery);
                              }).toList();

                        final rightTile = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0, vertical: 8.0),
                              child: Text('Recent Patient Records',
                                  style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w900,
                                      color: _primary)),
                            ),
                            const SizedBox(height: 16),
                            filteredNotes.isEmpty
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 40.0),
                                      child: Text(
                                        searchQuery.isEmpty
                                            ? 'No patient records found. Start a consultation!'
                                            : 'No records found for this patient.',
                                        style: TextStyle(
                                          color: _onSurfaceVariant,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  )
                                : GridView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    padding: const EdgeInsets.only(
                                        bottom: 40, top: 8),
                                    gridDelegate:
                                        SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: isDesktop ? 350 : 300,
                                      mainAxisSpacing: 24,
                                      crossAxisSpacing: 24,
                                      childAspectRatio: 1.3,
                                    ),
                                    itemCount: filteredNotes.length,
                                    itemBuilder: (context, index) {
                                      final note = filteredNotes[index];
                                      final isReport =
                                          note.containsKey('key_findings');
                                      return _buildPatientCard(note, isReport);
                                    },
                                  ),
                          ],
                        );

                        if (isDesktop) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 450, child: leftTile),
                              const SizedBox(width: 40),
                              Expanded(
                                child: SingleChildScrollView(
                                  child: rightTile,
                                ),
                              ),
                            ],
                          );
                        } else {
                          return SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                leftTile,
                                const SizedBox(height: 32),
                                rightTile,
                              ],
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
