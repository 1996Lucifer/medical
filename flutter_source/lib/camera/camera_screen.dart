import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../main.dart' show GlassCard, GlassBackground;
import '../network/api_routes.dart';
import '../network/network_manager.dart';
import 'camera_status_service.dart';
import 'camera_stream_view.dart';

// ── Data models ───────────────────────────────────────────────────────────────

class AttendanceRecord {
  final int id;
  final String staffName;
  final String role;
  // Null for non-face-match sources (e.g. "rfid") — a badge tap has no
  // face-match score to show.
  final double? confidence;
  final DateTime entryTime;
  final DateTime? lastSeen;
  final DateTime? exitTime;
  final int? cameraId;
  final String? cameraName;
  // "face" (default, camera recognition), "rfid" (badge tap), or "manual".
  final String source;

  AttendanceRecord({
    required this.id,
    required this.staffName,
    required this.role,
    required this.confidence,
    required this.entryTime,
    this.lastSeen,
    this.exitTime,
    this.cameraId,
    this.cameraName,
    this.source = 'face',
  });

  bool get isCheckedOut => exitTime != null;

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) => AttendanceRecord(
        id: j['id'],
        staffName: j['staff_name'],
        role: j['role'] ?? 'Medical Staff',
        confidence: j['confidence'] != null
            ? (j['confidence'] as num).toDouble()
            : null,
        entryTime: DateTime.parse(j['entry_time']),
        lastSeen:
            j['last_seen'] != null ? DateTime.parse(j['last_seen']) : null,
        exitTime:
            j['exit_time'] != null ? DateTime.parse(j['exit_time']) : null,
        cameraId: j['camera_id'],
        cameraName: j['camera_name'],
        source: j['source'] as String? ?? 'face',
      );
}

/// Small icon + tooltip distinguishing which channel produced an
/// AttendanceRecord, shared by every screen that lists attendance rows.
Widget attendanceSourceBadge(String source, {double size = 14}) {
  late final IconData icon;
  late final Color color;
  late final String label;
  switch (source) {
    case 'rfid':
      icon = Icons.nfc;
      color = Colors.blueAccent;
      label = 'RFID badge tap';
      break;
    case 'manual':
      icon = Icons.edit_note;
      color = Colors.orangeAccent;
      label = 'Manually recorded';
      break;
    case 'app':
      icon = Icons.smartphone;
      color = Colors.purpleAccent;
      label = 'App presence detection (Wi-Fi/geofence)';
      break;
    default:
      icon = Icons.face;
      color = Colors.tealAccent;
      label = 'Face recognition';
  }
  return Tooltip(
    message: label,
    child: Icon(icon, size: size, color: color),
  );
}

// ── Screen ────────────────────────────────────────────────────────────────────

class CameraScreen extends StatefulWidget {
  final int? initialExpandedCameraId;
  const CameraScreen({super.key, this.initialExpandedCameraId});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with SingleTickerProviderStateMixin {
  // Attendance
  List<AttendanceRecord> _attendance = [];
  WebSocketChannel? _eventsChannel;
  StreamSubscription? _eventsSub;

  // Sourced from GlobalCameraStatus (see initState/dispose) - this screen
  // used to open its own second raw WebSocket to the exact same
  // /api/cameras/ws/status endpoint that GlobalCameraStatus already
  // manages app-wide (started by MainShell), duplicating a live
  // connection with none of that shared service's reconnect logic.
  Map<int, bool> _cameraStatus = {};

  // Camera source state
  List<Map<String, dynamic>> _savedCameras = [];
  int? _expandedCameraId;
  final Map<int, GlobalKey> _streamKeys = {};

  // Aetheris colors
  Color get _primary => Theme.of(context).colorScheme.onSurface;
  Color get _onSurface => Theme.of(context).colorScheme.onSurface;
  Color get _onSurfaceVariant => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _primaryFixedDim => Theme.of(context).colorScheme.secondary;
  Color get _surfaceContainerHigh =>
      Theme.of(context).colorScheme.surfaceContainerHigh;
  Color get _surfaceContainerLowest =>
      Theme.of(context).colorScheme.surfaceContainerLowest;
  Color get _error => Theme.of(context).colorScheme.error;

  late AnimationController _pulseController;
  bool _showOverlays = true;

  @override
  void initState() {
    super.initState();
    _expandedCameraId = widget.initialExpandedCameraId;
    _fetchCameras();
    _connectEventsStream();
    _cameraStatus = GlobalCameraStatus.statuses.value;
    GlobalCameraStatus.statuses.addListener(_onGlobalStatusChanged);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
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
          if (event['event_type'] == 'Attendance' ||
              event['event_type'] == 'UnknownFaceDetected') {
            _fetchAttendance();
          }
          if (event['event_type'] == 'SpokenWarning') {
            final details = event['details'] as Map<String, dynamic>;
            final warningText = details['warning'] as String?;
            if (warningText != null && warningText.isNotEmpty) {
              debugPrint("Warning received: $warningText");
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

  void _onGlobalStatusChanged() {
    if (mounted) {
      setState(() => _cameraStatus = GlobalCameraStatus.statuses.value);
    }
  }

  String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  Future<void> _exportAttendanceLog() async {
    if (_attendance.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No attendance records to export.')),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln(
        'Staff Name,Role,Source,Confidence,Entry Time,Last Seen,Exit Time,Camera');
    for (final record in _attendance) {
      buffer.writeln([
        _csvEscape(record.staffName),
        _csvEscape(record.role),
        record.source,
        record.confidence?.toStringAsFixed(2) ?? '',
        record.entryTime.toIso8601String(),
        record.lastSeen?.toIso8601String() ?? '',
        record.exitTime?.toIso8601String() ?? '',
        _csvEscape(record.cameraName ?? ''),
      ].join(','));
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName =
          'attendance_log_${DateTime.now().millisecondsSinceEpoch}.csv';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(buffer.toString());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported to ${file.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  Future<void> _fetchAttendance() async {
    try {
      final resp = await NetworkManager.instance
          .get(ApiRoutes.attendance)
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body) as List<dynamic>;
        setState(() {
          _attendance = data.map((j) => AttendanceRecord.fromJson(j)).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _deleteAttendance(int id) async {
    await NetworkManager.instance
        .delete(ApiRoutes.attendanceDelete(id))
        .timeout(const Duration(seconds: 5))
        .catchError((_) => http.Response('', 500));
    _fetchAttendance();
  }

  Future<void> _fetchCameras() async {
    try {
      final resp = await NetworkManager.instance
          .get(ApiRoutes.cameras)
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200 && mounted) {
        setState(() {
          _savedCameras = (jsonDecode(resp.body) as List<dynamic>)
              .cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {}
  }

  GlobalKey _streamKey(int cameraId) =>
      _streamKeys.putIfAbsent(cameraId, GlobalKey.new);

  Widget _cameraTile(
    Map<String, dynamic> camera, {
    required bool isPrimary,
    required VoidCallback onTap,
  }) {
    final cameraId = camera['id'] as int;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPrimary
                  ? _primaryFixedDim.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.05),
              width: isPrimary ? 2 : 1,
            ),
            boxShadow: [
              if (isPrimary)
                BoxShadow(
                    color: _primaryFixedDim.withValues(alpha: 0.2),
                    blurRadius: 10,
                    spreadRadius: 2)
            ]),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraStreamView(
              key: _streamKey(cameraId),
              cameraId: cameraId,
              mode: _showOverlays ? 'ai' : 'manage',
              fit: BoxFit.contain,
            ),

            // Scanline overlay
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      _primaryFixedDim.withValues(alpha: 0.0),
                      _primaryFixedDim.withValues(alpha: 0.05),
                      _primaryFixedDim.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  )),
                ),
              ),
            ),

            Positioned(
              left: 16,
              top: 16,
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        if (_cameraStatus[cameraId] ?? false) ...[
                          FadeTransition(
                            opacity: _pulseController,
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                  color: Colors.redAccent,
                                  shape: BoxShape.circle),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text('LIVE',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1)),
                        ] else ...[
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                                color: Colors.grey.shade400,
                                shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text('OFFLINE',
                              style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1)),
                        ]
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      (camera['name'] as String).toUpperCase(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1),
                    ),
                  ),
                ],
              ),
            ),

            // Add top right overlay toggle if it is the first camera, just for visual parity with the mockup
            if (isPrimary)
              Positioned(
                right: 16,
                top: 16,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _showOverlays = !_showOverlays;
                      });
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('AI OVERLAYS',
                            style: TextStyle(
                                color: _showOverlays
                                    ? Colors.white
                                    : Colors.white54,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5)),
                        const SizedBox(width: 8),
                        Container(
                          width: 28,
                          height: 16,
                          decoration: BoxDecoration(
                              color: _showOverlays
                                  ? _primaryFixedDim
                                  : Colors.grey[800],
                              borderRadius: BorderRadius.circular(8)),
                          child: AnimatedAlign(
                            duration: const Duration(milliseconds: 200),
                            alignment: _showOverlays
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                                margin: const EdgeInsets.all(2),
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle)),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ),

            // Bottom controls for visual parity with mockup
            // Positioned(
            //   bottom: 16,
            //   left: 0,
            //   right: 0,
            //   child: IgnorePointer(
            //     child: Center(
            //       child: Container(
            //         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            //         decoration: BoxDecoration(
            //           color: Colors.black.withValues(alpha: 0.6),
            //           borderRadius: BorderRadius.circular(8),
            //         ),
            //         child: Row(
            //           mainAxisSize: MainAxisSize.min,
            //           children: [
            //             Container(width: 8, height: 8, color: _primaryFixedDim),
            //             const SizedBox(width: 16),
            //             const Icon(Icons.arrow_back_ios, size: 12, color: Colors.white70),
            //             const SizedBox(width: 16),
            //             const Icon(Icons.play_circle_outline, size: 20, color: _primaryFixedDim),
            //             const SizedBox(width: 16),
            //             const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white70),
            //             const SizedBox(width: 16),
            //             const Icon(Icons.photo_outlined, size: 16, color: Colors.white70),
            //           ],
            //         ),
            //       ),
            //     ),
            //   ),
            // ),

            if (isPrimary)
              Positioned(
                right: 16,
                bottom: 60,
                child: IconButton(
                  tooltip: 'Return to grid',
                  onPressed: () => setState(() => _expandedCameraId = null),
                  icon: const Icon(Icons.fullscreen_exit),
                  color: Colors.white,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.6),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cameraGrid({required bool isMobile}) {
    if (_savedCameras.isEmpty) {
      return Center(
        child: Text('No cameras configured.',
            style: TextStyle(color: _onSurfaceVariant)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = isMobile
            ? 1
            : _savedCameras.length <= 1
                ? 1
                : 2;
        const spacing = 16.0;
        final tileWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        final tileHeight = tileWidth * 9 / 16;
        final standardTileHeight = tileHeight.clamp(200.0, 400.0).toDouble();

        return GridView.builder(
          shrinkWrap: true,
          physics: const BouncingScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: tileWidth / standardTileHeight,
          ),
          itemCount: _savedCameras.length,
          itemBuilder: (ctx, i) {
            final camera = _savedCameras[i];
            return _cameraTile(
              camera,
              isPrimary: false,
              onTap: () =>
                  setState(() => _expandedCameraId = camera['id'] as int),
            );
          },
        );
      },
    );
  }

  Widget _focusedCameraView({required bool isMobile}) {
    Map<String, dynamic>? primary;
    for (final camera in _savedCameras) {
      if (camera['id'] == _expandedCameraId) {
        primary = camera;
        break;
      }
    }
    if (primary == null) {
      return _cameraGrid(isMobile: isMobile);
    }

    final secondary = _savedCameras
        .where((camera) => camera['id'] != _expandedCameraId)
        .toList();
    final railHeight = isMobile ? 120.0 : 160.0;

    return Column(
      children: [
        Expanded(
          child: _cameraTile(
            primary,
            isPrimary: true,
            onTap: () {},
          ),
        ),
        if (secondary.isNotEmpty) ...[
          const SizedBox(height: 16),
          SizedBox(
            height: railHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: secondary.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final camera = secondary[index];
                return SizedBox(
                  width: railHeight * 16 / 9,
                  child: _cameraTile(
                    camera,
                    isPrimary: false,
                    onTap: () =>
                        setState(() => _expandedCameraId = camera['id'] as int),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _eventsChannel?.sink.close();
    // Not GlobalCameraStatus.stopPolling() - MainShell owns that
    // app-session-scoped lifecycle (it starts polling once for the whole
    // authenticated app and stops it on logout), not this one screen.
    GlobalCameraStatus.statuses.removeListener(_onGlobalStatusChanged);
    _pulseController.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 900;

    Widget cameraPanel = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Live Camera Grid',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _primary)),
                  const SizedBox(height: 4),
                  Text(
                      'Real-time neural monitoring active across 4 primary zones.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: _onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (!isMobile)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _surfaceContainerHigh.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: Row(
                  children: [
                    Text('Auto-Rotation',
                        style: TextStyle(
                            color: _onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(width: 12),
                    Container(
                      width: 40,
                      height: 20,
                      decoration: BoxDecoration(
                          color: _surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(10)),
                      child: Stack(
                        children: [
                          Positioned(
                            right: 4,
                            top: 4,
                            child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                    color: _primaryFixedDim,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                          color: _primaryFixedDim,
                                          blurRadius: 4)
                                    ])),
                          )
                        ],
                      ),
                    )
                  ],
                ),
              )
          ],
        ),
        const SizedBox(height: 24),
        isMobile
            ? SizedBox(
                height: _expandedCameraId == null ? 400 : 500,
                child: _expandedCameraId == null
                    ? _cameraGrid(isMobile: true)
                    : _focusedCameraView(isMobile: true),
              )
            : Expanded(
                child: _expandedCameraId == null
                    ? _cameraGrid(isMobile: false)
                    : _focusedCameraView(isMobile: false),
              ),
      ],
    );

    Widget attendancePanel = GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Staff Attendance',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _primary)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text('Recent Detections',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: _onSurfaceVariant, fontSize: 14)),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: _primaryFixedDim.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4)),
                      child: Text('AUTO-SYNC ON',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: _primaryFixedDim,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    )
                  ],
                )
              ],
            ),
          ),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
          Expanded(
            child: _attendanceList(),
          ),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _exportAttendanceLog,
                icon: const Icon(Icons.download, size: 20),
                label: const Text('Export Attendance Log',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryFixedDim,
                  foregroundColor: const Color(0xFF00382d),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          )
        ],
      ),
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: GlassBackground(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: isMobile
                    ? ListView(
                        children: [
                          cameraPanel,
                          const SizedBox(height: 24),
                          SizedBox(height: 500, child: attendancePanel),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: cameraPanel,
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 1,
                            child: attendancePanel,
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attendanceList() {
    if (_attendance.isEmpty) {
      return Center(
        child: Text('No recent detections.',
            style: TextStyle(color: _onSurfaceVariant)),
      );
    }

    // One row per staff member, not one row per check-in/check-out session -
    // someone stepping out and back in during the day legitimately produces
    // several AttendanceRecord rows for the same person, which used to show
    // as that many separate cards. Groups by name, preserving _attendance's
    // existing (newest-first) order for both the group order and each
    // group's session order.
    final groups = <String, List<AttendanceRecord>>{};
    for (final r in _attendance) {
      groups.putIfAbsent(r.staffName, () => []).add(r);
    }
    final groupNames = groups.keys.toList();

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: groupNames.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final sessions = groups[groupNames[i]]!;
        final first = sessions.first;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.transparent,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child:
                        Icon(Icons.person, color: _onSurfaceVariant, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(first.staffName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: _primary,
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                  ),
                  if (sessions.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: _primaryFixedDim.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4)),
                      child: Text('${sessions.length}x',
                          style: TextStyle(
                              color: _primaryFixedDim,
                              fontSize: 10,
                              fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Padding(
                // Indenting under the avatar/name would be nice, but this
                // panel is only ~190px wide - that indent alone was most of
                // why every session row overflowed on the right.
                padding: const EdgeInsets.only(left: 8),
                child: Text(first.role,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _onSurfaceVariant, fontSize: 12)),
              ),
              const SizedBox(height: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final r in sessions) ...[
                    _attendanceSessionPhrase(r),
                    if (r != sessions.last) const SizedBox(height: 6),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// One "08:15 - 08:55" (or "08:15 - Present" while still checked in) line
  /// per session, with that session's confidence/source and, only for the
  /// still-open session, its own checkout/delete actions - each session is
  /// independently a real check-in/check-out record, so these apply to that
  /// one row, not the whole person.
  Widget _attendanceSessionPhrase(AttendanceRecord r) {
    String hm(DateTime d) {
      final t = d.toLocal();
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }

    final phrase = r.exitTime != null
        ? '${hm(r.entryTime)} – ${hm(r.exitTime!)}'
        : '${hm(r.entryTime)} – Present';
    final pct =
        r.confidence != null ? (r.confidence! * 100).toStringAsFixed(1) : null;

    return Row(
      children: [
        attendanceSourceBadge(r.source, size: 11),
        const SizedBox(width: 6),
        Expanded(
          child: Text(phrase,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _onSurfaceVariant, fontSize: 12)),
        ),
        if (pct != null) ...[
          const SizedBox(width: 4),
          Text('$pct%',
              style: TextStyle(
                  color: _onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
        if (!r.isCheckedOut) ...[
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.logout, size: 14, color: Colors.orange),
            tooltip: 'Checkout',
            onPressed: () async {
              await NetworkManager.instance
                  .post(ApiRoutes.attendanceCheckout(r.id));
              _fetchAttendance();
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 14, color: _error),
            onPressed: () => _deleteAttendance(r.id),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ],
    );
  }
}
