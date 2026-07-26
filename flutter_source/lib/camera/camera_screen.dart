import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../main.dart' show GlassCard, GlassBackground;
import '../network/api_routes.dart';
import '../network/network_manager.dart';
import 'camera_stream_view.dart';

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
        lastSeen:
            j['last_seen'] != null ? DateTime.parse(j['last_seen']) : null,
        exitTime:
            j['exit_time'] != null ? DateTime.parse(j['exit_time']) : null,
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

class _CameraScreenState extends State<CameraScreen> with SingleTickerProviderStateMixin {
  // Attendance
  List<AttendanceRecord> _attendance = [];
  WebSocketChannel? _eventsChannel;
  StreamSubscription? _eventsSub;

  WebSocketChannel? _statusChannel;
  StreamSubscription? _statusSub;
  Map<int, bool> _cameraStatus = {};

  // Camera source state
  List<Map<String, dynamic>> _savedCameras = [];
  int? _expandedCameraId;
  final Map<int, GlobalKey> _streamKeys = {};

  // Aetheris colors
  static const Color _primary = Color(0xFFffffff);
  static const Color _onSurface = Color(0xFFd6e3ff);
  static const Color _onSurfaceVariant = Color(0xFFbacac3);
  static const Color _primaryFixedDim = Color(0xFF38debb);
  static const Color _surfaceContainerHigh = Color(0xFF1c2a41);
  static const Color _surfaceContainerLowest = Color(0xFF010e24);
  static const Color _error = Color(0xFFffb4ab);
  
  late AnimationController _pulseController;
  int _primaryCameraIndex = 0;
  bool _showOverlays = true;

  @override
  void initState() {
    super.initState();
    _fetchCameras();
    _connectEventsStream();
    _connectStatusStream();
    
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

  void _connectStatusStream() {
    try {
      final wsUri = Uri.parse(ApiRoutes.camerasStatusWs);
      _statusChannel = WebSocketChannel.connect(wsUri);
      
      _statusSub = _statusChannel!.stream.listen((message) {
        if (mounted) {
          final data = jsonDecode(message) as Map<String, dynamic>;
          setState(() {
            _cameraStatus = data.map((k, v) => MapEntry(int.parse(k), v as bool));
          });
        }
      }, onError: (_) {}, onDone: () {});
    } catch (_) {}
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
            color: isPrimary ? _primaryFixedDim.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.05),
            width: isPrimary ? 2 : 1,
          ),
          boxShadow: [
            if (isPrimary) BoxShadow(color: _primaryFixedDim.withValues(alpha: 0.2), blurRadius: 10, spreadRadius: 2)
          ]
        ),
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
                    )
                  ),
                ),
              ),
            ),
            
            Positioned(
              left: 16,
              top: 16,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                              width: 6, height: 6,
                              decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        ] else ...[
                          Container(
                            width: 6, height: 6,
                            decoration: BoxDecoration(color: Colors.grey.shade400, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text('OFFLINE', style: TextStyle(color: Colors.grey.shade400, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        ]
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      (camera['name'] as String).toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                        Text('AI OVERLAYS', style: TextStyle(color: _showOverlays ? Colors.white : Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                        const SizedBox(width: 8),
                        Container(
                          width: 28, height: 16,
                          decoration: BoxDecoration(
                            color: _showOverlays ? _primaryFixedDim : Colors.grey[800], 
                            borderRadius: BorderRadius.circular(8)
                          ),
                          child: AnimatedAlign(
                            duration: const Duration(milliseconds: 200),
                            alignment: _showOverlays ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(margin: const EdgeInsets.all(2), width: 12, height: 12, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ),

            // Bottom controls for visual parity with mockup
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 8, height: 8, color: _primaryFixedDim),
                        const SizedBox(width: 16),
                        const Icon(Icons.arrow_back_ios, size: 12, color: Colors.white70),
                        const SizedBox(width: 16),
                        const Icon(Icons.play_circle_outline, size: 20, color: _primaryFixedDim),
                        const SizedBox(width: 16),
                        const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white70),
                        const SizedBox(width: 16),
                        const Icon(Icons.photo_outlined, size: 16, color: Colors.white70),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            
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
      return const Center(
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
        final spacing = 16.0;
        final tileWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;
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
              onTap: () => setState(() => _expandedCameraId = camera['id'] as int),
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
    _statusSub?.cancel();
    _statusChannel?.sink.close();
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
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Live Camera Grid', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _primary)),
                SizedBox(height: 4),
                Text('Real-time neural monitoring active across 4 primary zones.', style: TextStyle(fontSize: 14, color: _onSurfaceVariant)),
              ],
            ),
            if (!isMobile)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _surfaceContainerHigh.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: Row(
                  children: [
                    const Text('Auto-Rotation', style: TextStyle(color: _onSurface, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 12),
                    Container(
                      width: 40, height: 20,
                      decoration: BoxDecoration(color: _surfaceContainerLowest, borderRadius: BorderRadius.circular(10)),
                      child: Stack(
                        children: [
                          Positioned(
                            right: 4, top: 4,
                            child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: _primaryFixedDim, shape: BoxShape.circle, boxShadow: [BoxShadow(color: _primaryFixedDim, blurRadius: 4)])),
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
                const Text('Staff Attendance', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _primary)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Recent Detections', style: TextStyle(color: _onSurfaceVariant, fontSize: 14)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: _primaryFixedDim.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                      child: const Text('AUTO-SYNC ON', style: TextStyle(color: _primaryFixedDim, fontSize: 10, fontWeight: FontWeight.bold)),
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
                onPressed: () {},
                icon: const Icon(Icons.download, size: 20),
                label: const Text('Export Attendance Log', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryFixedDim,
                  foregroundColor: const Color(0xFF00382d),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          )
        ],
      ),
    );

    Widget topNavBar = Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        children: [
          const Text('Aegis AI Command', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(width: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _surfaceContainerHigh.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: _primaryFixedDim, shape: BoxShape.circle, boxShadow: [BoxShadow(color: _primaryFixedDim, blurRadius: 4)])),
                const SizedBox(width: 8),
                const Text('Core AI: Optimal', style: TextStyle(color: _primaryFixedDim, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const Text('48.2 TFLOPS Processing', style: TextStyle(color: _onSurfaceVariant, fontSize: 12)),
          const Spacer(),
          const Icon(Icons.notifications_none, color: _onSurfaceVariant, size: 20),
          const SizedBox(width: 16),
          const Icon(Icons.settings_outlined, color: _onSurfaceVariant, size: 20),
          const SizedBox(width: 16),
          const Icon(Icons.view_agenda_outlined, color: _onSurfaceVariant, size: 20),
          const SizedBox(width: 16),
          const CircleAvatar(radius: 14, backgroundColor: _primaryFixedDim, child: Icon(Icons.person, size: 18, color: Color(0xFF041329))),
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
              if (!isMobile) topNavBar,
              Expanded(
                child: isMobile
                    ? ListView(
                        children: [
                          if (isMobile) topNavBar,
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
      return const Center(
        child: Text('No recent detections.', style: TextStyle(color: _onSurfaceVariant)),
      );
    }
    
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _attendance.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final r = _attendance[i];
        final t = r.entryTime.toLocal();
        final entryStr = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        final pct = (r.confidence * 100).toStringAsFixed(1);
        final pctValue = r.confidence;

        // Use a mock role
        final mockRole = i % 2 == 0 ? 'Cardiology' : 'Nurse Ops';
        
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
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: _surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: const Icon(Icons.person, color: _onSurfaceVariant, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.staffName, style: const TextStyle(color: _primary, fontSize: 14, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(mockRole, style: const TextStyle(color: _onSurfaceVariant, fontSize: 12)),
                        const SizedBox(height: 2),
                        Text('• $entryStr', style: const TextStyle(color: _onSurfaceVariant, fontSize: 11)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('CONFIDENCE', style: TextStyle(color: _primaryFixedDim, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      Text('$pct%', style: const TextStyle(color: _primary, fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                height: 6,
                decoration: BoxDecoration(color: _surfaceContainerHigh.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(3)),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: pctValue,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _primaryFixedDim,
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: [BoxShadow(color: _primaryFixedDim.withValues(alpha: 0.5), blurRadius: 4)]
                    ),
                  ),
                ),
              ),
              
              if (!r.isCheckedOut)
                Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.logout, size: 16, color: Colors.orange),
                        tooltip: 'Checkout',
                        onPressed: () async {
                          await NetworkManager.instance.post(ApiRoutes.attendanceCheckout(r.id));
                          _fetchAttendance();
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 16, color: _error),
                        onPressed: () => _deleteAttendance(r.id),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                )
            ],
          ),
        );
      },
    );
  }
}
