import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../network/api_routes.dart';
import '../network/network_manager.dart';
import 'report_analysis_view.dart';
import '../main.dart' show GlassBackground, GlassCard;
import '../storage/secure_storage_service.dart';
import 'soap_note_view.dart';

class ConsultationScreen extends StatefulWidget {
  const ConsultationScreen({super.key});

  @override
  State<ConsultationScreen> createState() => _ConsultationScreenState();
}

class _ConsultationScreenState extends State<ConsultationScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final AudioRecorder _audioRecorder = AudioRecorder();
  TextEditingController _patientNameController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  
  bool _isRecording = false;
  bool _isProcessing = false;
  
  Map<String, dynamic>? _currentNote;
  Map<String, dynamic>? _currentReport;
  
  List<Map<String, dynamic>> _savedNotes = [];
  List<String> _availablePatients = [];

  @override
  void initState() {
    super.initState();
    _loadSavedNotes();
    _fetchPatients();
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    _patientNameController.dispose();
    super.dispose();
  }

  Future<void> _fetchPatients() async {
    try {
      final response = await http.get(Uri.parse('${ApiRoutes.baseUrl}/api/patients'));
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
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error starting recording: $e')),
      );
    }
  }

  Future<void> _stopRecordingAndProcess() async {
    try {
      final pathOrUrl = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _isProcessing = true;
      });

      if (pathOrUrl != null) {
        await _uploadAudioForAnalysis(pathOrUrl);
      } else {
        setState(() => _isProcessing = false);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error stopping recording: $e')),
      );
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _uploadAudioForAnalysis(String pathOrUrl) async {
    try {
      final request = NetworkManager.instance.multipartRequest('POST', '${ApiRoutes.baseUrl}/api/consultations?patient_name=${Uri.encodeComponent(_patientNameController.text.trim())}');
      
      if (kIsWeb) {
        final response = await http.get(Uri.parse(pathOrUrl));
        request.files.add(http.MultipartFile.fromBytes('file', response.bodyBytes, filename: 'audio.webm'));
      } else {
        request.files.add(await http.MultipartFile.fromPath('file', pathOrUrl));
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        await SecureStorageService.instance.savePatientNote(_patientNameController.text.trim(), data);
        _loadSavedNotes(); 
        _openDrawerWithNote(data);
      } else {
        throw Exception('Server error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI Processing failed: $e')),
      );
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _captureAndAnalyzeImage() async {
    if (_patientNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter patient name first')),
      );
      return;
    }

    try {
      final XFile? image = await _imagePicker.pickImage(source: ImageSource.camera);
      if (image == null) return;

      setState(() {
        _isProcessing = true;
      });

      final request = NetworkManager.instance.multipartRequest('POST', '${ApiRoutes.baseUrl}/api/analysis/report');
      request.fields['patient_name'] = _patientNameController.text.trim();
      
      final bytes = await image.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: image.name));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        await SecureStorageService.instance.savePatientNote(_patientNameController.text.trim(), data);
        _loadSavedNotes(); 
        _openDrawerWithReport(data);
      } else {
        throw Exception('Server error: ${response.statusCode} - ${response.body}');
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
    return Card(
      elevation: 8,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          if (isReport) {
            _openDrawerWithReport(note);
          } else {
            _openDrawerWithNote(note);
          }
        },
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: isReport ? [Colors.blue.shade50, Colors.white] : [Colors.teal.shade50, Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: isReport ? Colors.blue.shade100 : Colors.teal.shade100,
                    child: Icon(isReport ? Icons.analytics : Icons.description, color: isReport ? Colors.blue : Colors.teal, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(note['patient_name'] ?? 'Unknown Patient', 
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Color(0xFF1E293B)),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(note['date']?.substring(0,10) ?? '', style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isReport ? Colors.blue.shade200 : Colors.teal.shade200,
                      borderRadius: BorderRadius.circular(20)
                    ),
                    child: Text(isReport ? 'AI Report' : 'SOAP Note', 
                      style: TextStyle(color: isReport ? Colors.blue.shade900 : Colors.teal.shade900, fontSize: 12, fontWeight: FontWeight.bold)),
                  )
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Clinical Copilot',
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A), fontSize: 24),
        ),
        backgroundColor: Colors.white.withOpacity(0.6),
        elevation: 0,
        actions: const [
          SizedBox.shrink(), // Hides the default hamburger menu for the endDrawer
        ],
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(color: Colors.transparent),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.black.withOpacity(0.05), height: 1.0),
        ),
      ),
      endDrawer: Drawer(
        width: MediaQuery.of(context).size.width > 800 ? 600 : MediaQuery.of(context).size.width * 0.85,
        backgroundColor: const Color(0xFFF8FAFC).withOpacity(0.95),
        elevation: 24,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(left: Radius.circular(32))),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Patient Record', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                    Container(
                      decoration: const BoxDecoration(color: Colors.black12, shape: BoxShape.circle),
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.black87),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    )
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1),
              if (_currentNote != null)
                Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: SoapNoteView(noteData: _currentNote!)))
              else if (_currentReport != null)
                Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ReportAnalysisView(reportData: _currentReport!))),
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
                  const SizedBox(height: 80), // For AppBar
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isDesktop = constraints.maxWidth > 800;
                        
                        final leftTile = GlassCard(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Record Consultation\n& Analyze Reports',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                              ),
                              const SizedBox(height: 24),
                              
                              // Patient Name Autocomplete
                              Autocomplete<String>(
                                optionsBuilder: (TextEditingValue textEditingValue) {
                                  if (textEditingValue.text.isEmpty) {
                                    return const Iterable<String>.empty();
                                  }
                                  return _availablePatients.where((String option) {
                                    return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                                  });
                                },
                                onSelected: (String selection) {
                                  _patientNameController.text = selection;
                                },
                                optionsViewBuilder: (context, onSelected, options) {
                                  return Align(
                                    alignment: Alignment.topLeft,
                                    child: Material(
                                      elevation: 8,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      color: Colors.white,
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(maxHeight: 250, maxWidth: 350),
                                        child: ListView.builder(
                                          padding: EdgeInsets.zero,
                                          shrinkWrap: true,
                                          itemCount: options.length,
                                          itemBuilder: (context, index) {
                                            final option = options.elementAt(index);
                                            return InkWell(
                                              onTap: () => onSelected(option),
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                                child: Text(option, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                                  if (_patientNameController != controller) {
                                    _patientNameController = controller;
                                    _patientNameController.addListener(() {
                                      setState(() {}); // Rebuild to filter the grid
                                    });
                                  }
                                  return Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]
                                    ),
                                    child: TextField(
                                      controller: controller,
                                      focusNode: focusNode,
                                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                                      decoration: InputDecoration(
                                        labelText: 'Patient Name (Search or Create New)',
                                        labelStyle: const TextStyle(color: Colors.black54),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                                        prefixIcon: const Icon(Icons.person_search_rounded, color: Colors.teal),
                                        filled: true,
                                        fillColor: Colors.white,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16)
                                      ),
                                      enabled: !_isRecording && !_isProcessing,
                                    ),
                                  );
                                },
                              ),
                              
                              const SizedBox(height: 24),
                              
                              if (_isProcessing)
                                const Column(
                                  children: [
                                    CircularProgressIndicator(color: Colors.teal, strokeWidth: 3),
                                    SizedBox(height: 20),
                                    Text('Processing with Gemini AI...', style: TextStyle(color: Colors.black54, fontSize: 16, fontWeight: FontWeight.w600)),
                                  ],
                                )
                              else
                                Column(
                                  children: [
                                    GestureDetector(
                                      onTap: _isRecording ? _stopRecordingAndProcess : _startRecording,
                                      child: AnimatedContainer(
                                        duration: const Duration(milliseconds: 300),
                                        width: 80, height: 80,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: _isRecording ? [Colors.redAccent, Colors.red.shade900] : [Colors.tealAccent.shade400, Colors.teal.shade700],
                                            begin: Alignment.topLeft, end: Alignment.bottomRight,
                                          ),
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(color: (_isRecording ? Colors.red : Colors.teal).withOpacity(0.4), blurRadius: _isRecording ? 24 : 16, spreadRadius: _isRecording ? 4 : 0, offset: const Offset(0, 8)),
                                          ],
                                        ),
                                        child: Icon(_isRecording ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 40),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text('Record Audio', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
                                    const SizedBox(height: 24),
                                    ElevatedButton.icon(
                                      onPressed: _isRecording ? null : _captureAndAnalyzeImage,
                                      icon: const Icon(Icons.document_scanner_rounded, size: 24),
                                      label: const Text('Analyze Report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blueAccent.shade700, foregroundColor: Colors.white,
                                        elevation: 8, shadowColor: Colors.blueAccent.withOpacity(0.5),
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        );

                        final searchQuery = _patientNameController.text.trim().toLowerCase();
                        final filteredNotes = searchQuery.isEmpty 
                          ? _savedNotes 
                          : _savedNotes.where((note) {
                              final name = (note['patient_name'] as String? ?? '').toLowerCase();
                              return name.contains(searchQuery);
                            }).toList();

                        final rightTile = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                              child: Text('Recent Patient Records', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                            ),
                            Expanded(
                              child: filteredNotes.isEmpty 
                                ? Center(child: Text(searchQuery.isEmpty ? 'No patient records found. Start a consultation!' : 'No records found for this patient.', style: const TextStyle(color: Colors.black54, fontSize: 16)))
                                : GridView.builder(
                                    padding: const EdgeInsets.only(bottom: 40, top: 8),
                                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: isDesktop ? 350 : 300,
                                      mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 1.3,
                                    ),
                                    itemCount: filteredNotes.length,
                                    itemBuilder: (context, index) {
                                      final note = filteredNotes[index];
                                      final isReport = note.containsKey('key_findings');
                                      return _buildPatientCard(note, isReport);
                                    },
                                  ),
                            ),
                          ],
                        );

                        if (isDesktop) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 400, child: leftTile),
                              const SizedBox(width: 32),
                              Expanded(child: rightTile),
                            ],
                          );
                        } else {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              leftTile,
                              const SizedBox(height: 24),
                              Expanded(child: rightTile),
                            ],
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
