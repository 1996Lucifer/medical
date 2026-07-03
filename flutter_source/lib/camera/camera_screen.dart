import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../main.dart' show GlassCard, GlassBackground;
import '../network/api_routes.dart';
import '../network/network_manager.dart';
import 'camera_stream_view.dart';
import 'camera_status_service.dart';

// ── Data models ───────────────────────────────────────────────────────────────

class AttendanceRecord {
  final int id;
  final String staffName;
  final double confidence;
  final DateTime entryTime;
  final DateTime? lastSeen;
  final DateTime? exitTime;
  final int? cameraId;
  final String? cameraName;

  AttendanceRecord({
    required this.id,
    required this.staffName,
    required this.confidence,
    required this.entryTime,
    this.lastSeen,
    this.exitTime,
    this.cameraId,
    this.cameraName,
  });

  bool get isCheckedOut => exitTime != null;

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) => AttendanceRecord(
        id: j['id'],
        staffName: j['staff_name'],
        confidence: (j['confidence'] as num).toDouble(),
        entryTime: DateTime.parse(j['entry_time']),
        lastSeen: j['last_seen'] != null ? DateTime.parse(j['last_seen']) : null,
        exitTime: j['exit_time'] != null ? DateTime.parse(j['exit_time']) : null,
        cameraId: j['camera_id'],
        cameraName: j['camera_name'],
      );
}

// ── Screen ────────────────────────────────────────────────────────────────────

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {

  // Attendance
  List<AttendanceRecord> _attendance = [];
  WebSocketChannel? _eventsChannel;
  StreamSubscription? _eventsSub;

  // Camera source state
  List<Map<String, dynamic>> _savedCameras = [];
  Map<String, dynamic>? _selectedCamera;   // picked from saved list

  // Staff list is now handled in SettingsScreen

  @override
  void initState() {
    super.initState();
    _fetchCameras();
    // _connectEventsStream();

  }

// ── Attendance ────────────────────────────────────────────────────────────
  void _connectEventsStream() {
    _fetchAttendance();
    try {
      final wsUri = Uri.parse(ApiRoutes.eventsWs);
      _eventsChannel = WebSocketChannel.connect(wsUri);
      bool isReconnecting = false;
      void scheduleReconnect() {
        if (mounted && !isReconnecting) {
          isReconnecting = true;
          Future.delayed(const Duration(seconds: 5), _connectEventsStream);
        }
      }

      _eventsSub = _eventsChannel!.stream.listen((message) {
        if (mounted) {
          final event = jsonDecode(message);
          if (event['event_type'] == 'Attendance' || event['event_type'] == 'UnknownFaceDetected') {
            _fetchAttendance();
          }
          if (event['event_type'] == 'SpokenWarning') {
            final details = event['details'] as Map<String, dynamic>;
            final warningText = details['warning'] as String?;
            if (warningText != null && warningText.isNotEmpty) {
              _speakWarning(warningText);
            }
          }
        }
      }, onError: (_) {
        scheduleReconnect();
      }, onDone: () {
        scheduleReconnect();
      });
    } catch (_) {}
  }

  final FlutterTts _flutterTts = FlutterTts();

  Future<void> _speakWarning(String text) async {
    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint("TTS Error: $e");
    }
  }

  Future<void> _fetchAttendance() async {
    try {
      final resp = await NetworkManager.instance.get(ApiRoutes.attendance)
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body) as List<dynamic>;
        setState(() { _attendance = data.map((j) => AttendanceRecord.fromJson(j)).toList(); });
      }
    } catch (_) {}
  }

  Future<void> _deleteAttendance(int id) async {
    await NetworkManager.instance.delete(ApiRoutes.attendanceDelete(id))
        .timeout(const Duration(seconds: 5))
        .catchError((_) => http.Response('', 500));
    _fetchAttendance();
  }



  Future<void> _fetchCameras() async {
    try {
      final resp = await NetworkManager.instance.get(ApiRoutes.cameras)
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200 && mounted) {
        setState(() {
          _savedCameras = (jsonDecode(resp.body) as List<dynamic>).cast<Map<String, dynamic>>();
          if (_savedCameras.isNotEmpty && _selectedCamera == null) {
            // _selectedCamera = _savedCameras.first;
          }
        });
      }
    } catch (_) {}
  }


  @override
  void dispose() {
    _eventsSub?.cancel();
    _eventsChannel?.sink.close();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 768;

    Widget cameraPanel = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Camera selection chips ──────────────────────────────────
        if (_savedCameras.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No cameras configured. Add them in Settings.',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: ValueListenableBuilder<Map<int, bool>>(
              valueListenable: GlobalCameraStatus.statuses,
              builder: (context, statuses, _) {
                return Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: _savedCameras.map((camera) {
                    final isSelected = _selectedCamera?['id'] == camera['id'];
                    final isOnline = statuses[camera['id']] ?? false;
                    return ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(camera['name']),
                          const SizedBox(width: 6),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: isOnline ? Colors.green : Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                      selected: isSelected,
                      onSelected: (selected) async {
                        if (selected) {
                          setState(() => _selectedCamera = camera);
                        }
                      },
                      selectedColor: Colors.teal.shade50,
                      checkmarkColor: Colors.teal.shade700,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.teal.shade800 : Colors.black87,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      avatar: Icon(Icons.videocam,
                          size: 16,
                          color: isSelected ? Colors.teal.shade700 : Colors.grey.shade600),
                    );
                  }).toList(),
                );
              }
            ),
          ),
        const SizedBox(height: 12),
        // Video box
        isMobile
            ? AspectRatio(
                aspectRatio: 4 / 3,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(color: Colors.grey.shade800),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: _selectedCamera != null
                    ? CameraStreamView(cameraId: _selectedCamera!['id'])
                    : const Center(child: Text('No camera selected', style: TextStyle(color: Colors.white54))),
                ),
              )
            : Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(color: Colors.grey.shade800),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: _selectedCamera != null
                    ? CameraStreamView(cameraId: _selectedCamera!['id'])
                    : const Center(child: Text('No camera selected', style: TextStyle(color: Colors.white54))),
                ),
              ),
      ],
    );

    Widget attendancePanel = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _attendanceHeader(),
        const SizedBox(height: 10),
        isMobile
            ? SizedBox(
                height: 350,
                child: _attendanceList(),
              )
            : Expanded(
                child: _attendanceList(),
              ),
      ],
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'AI Camera Stream',
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
        ),
        backgroundColor: Colors.white.withOpacity(0.6),
        elevation: 0,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.transparent),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.black.withOpacity(0.05), height: 1.0),
        ),
        actions: [
          if (_selectedCamera != null)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton.icon(
                onPressed: () {
                  setState(() => _selectedCamera = null);
                },
                icon: const Icon(Icons.stop_circle, color: Color(0xFFF43F5E), size: 20),
                label: const Text('Disconnect', style: TextStyle(color: Color(0xFFF43F5E), fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
      body: GlassBackground(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: isMobile
              ? SingleChildScrollView(
                  child: Column(
                    children: [
                      GlassCard(
                        padding: const EdgeInsets.all(16),
                        child: cameraPanel,
                      ),
                      const SizedBox(height: 16),
                      GlassCard(
                        padding: const EdgeInsets.all(16),
                        child: attendancePanel,
                      ),
                    ],
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: GlassCard(
                        padding: const EdgeInsets.all(16),
                        child: cameraPanel,
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 320,
                      child: GlassCard(
                        padding: const EdgeInsets.all(16),
                        child: attendancePanel,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _attendanceHeader() {
    final today = DateTime.now();
    return Row(children: [
      const Icon(Icons.how_to_reg, size: 20),
      const SizedBox(width: 6),
      Expanded(
        child: Text('Attendance — ${today.day}/${today.month}/${today.year}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ),
      IconButton(
        icon: const Icon(Icons.refresh, size: 18),
        onPressed: _fetchAttendance,
        tooltip: 'Refresh',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
      ),
    ]);
  }

  Widget _attendanceList() {
    if (_attendance.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text('No attendance records yet.\nFace detected = auto marked.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _attendance.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final r = _attendance[i];
          final t = r.entryTime.toLocal();
          final entryStr =
              '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
          final pct = (r.confidence * 100).toStringAsFixed(0);

          String? lastSeenStr;
          if (r.lastSeen != null) {
            final ls = r.lastSeen!.toLocal();
            lastSeenStr =
                '${ls.hour.toString().padLeft(2, '0')}:${ls.minute.toString().padLeft(2, '0')}';
          }
          String? exitStr;
          if (r.exitTime != null) {
            final ex = r.exitTime!.toLocal();
            exitStr =
                '${ex.hour.toString().padLeft(2, '0')}:${ex.minute.toString().padLeft(2, '0')}';
          }

          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            leading: CircleAvatar(
              radius: 18,
              backgroundColor:
                  r.isCheckedOut ? Colors.grey.shade200 : Colors.green.shade100,
              child: Text(r.staffName[0].toUpperCase(),
                  style: TextStyle(
                      color: r.isCheckedOut
                          ? Colors.grey.shade600
                          : Colors.green.shade700,
                      fontWeight: FontWeight.bold)),
            ),
            title: Row(children: [
              Expanded(
                child: Text(r.staffName,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              Text('$pct%',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600)),
            ]),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Entry → Last seen / Exit
                Row(children: [
                  const Icon(Icons.login, size: 11, color: Colors.grey),
                  const SizedBox(width: 3),
                  Text('In: $entryStr', style: const TextStyle(fontSize: 10)),
                  if (exitStr != null) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.logout, size: 11, color: Colors.red),
                    const SizedBox(width: 3),
                    Text('Out: $exitStr',
                        style: const TextStyle(fontSize: 10, color: Colors.red)),
                  ] else if (lastSeenStr != null) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.visibility, size: 11, color: Colors.grey),
                    const SizedBox(width: 3),
                    Text('Last: $lastSeenStr',
                        style: const TextStyle(fontSize: 10)),
                  ],
                ]),
                // Camera / location badge
                if (r.cameraName != null)
                  Row(children: [
                    const Icon(Icons.videocam, size: 11, color: Colors.blue),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(r.cameraName!,
                          style: const TextStyle(
                              fontSize: 10, color: Colors.blue),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!r.isCheckedOut)
                  IconButton(
                    icon: const Icon(Icons.logout, size: 16,
                        color: Colors.orange),
                    tooltip: 'Checkout',
                    onPressed: () async {
                      await NetworkManager.instance.post(ApiRoutes.attendanceCheckout(r.id));
                      _fetchAttendance();
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 16, color: Colors.red),
                  onPressed: () => _deleteAttendance(r.id),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            isThreeLine: r.cameraName != null,
          );
        },

      ),
    );
  }
}
