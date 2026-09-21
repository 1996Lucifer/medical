import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../network/api_routes.dart';
import '../network/network_manager.dart';

class TrackedUser {
  final int attendanceSessionId;
  final int? staffId;
  final String staffName;
  final String? department;
  final int? floorId;
  final double? x;
  final double? y;
  final String? areaName;
  final double? accuracyM;
  final double? confidence;
  final String? source;
  final String status; // active | paused_outside_geofence | stopped
  final DateTime trackingStartedAt;
  final DateTime updatedAt;

  TrackedUser({
    required this.attendanceSessionId,
    required this.staffId,
    required this.staffName,
    required this.department,
    required this.floorId,
    required this.x,
    required this.y,
    required this.areaName,
    required this.accuracyM,
    required this.confidence,
    required this.source,
    required this.status,
    required this.trackingStartedAt,
    required this.updatedAt,
  });

  factory TrackedUser.fromJson(Map<String, dynamic> j) => TrackedUser(
        attendanceSessionId: j['attendance_session_id'],
        staffId: j['staff_id'],
        staffName: j['staff_name'] ?? 'Unknown',
        department: j['department'],
        floorId: j['floor_id'],
        x: (j['x'] as num?)?.toDouble(),
        y: (j['y'] as num?)?.toDouble(),
        areaName: j['area_name'],
        accuracyM: (j['accuracy_m'] as num?)?.toDouble(),
        confidence: (j['confidence'] as num?)?.toDouble(),
        source: j['source'],
        status: j['status'] ?? 'active',
        trackingStartedAt: DateTime.tryParse(j['tracking_started_at'] ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(j['updated_at'] ?? '') ?? DateTime.now(),
      );

  bool get isStale => DateTime.now().difference(updatedAt) > const Duration(seconds: 45);
}

/// Entries older than this are pruned outright rather than just dimmed as
/// stale - a dropped connection, crashed client, or missed
/// session_stopped/session_left_floor message would otherwise leave them in
/// [IndoorTrackingWsClient.users] forever.
const _maxTrackedAge = Duration(minutes: 5);

/// Live feed of tracked users on one floor. Auto-reconnects, matching
/// camera/camera_status_service.dart's GlobalCameraStatus pattern - but
/// this one is per-floor and instance-based (an admin might watch several
/// floors across tabs) rather than a single global singleton.
class IndoorTrackingWsClient {
  final int floorId;
  final ValueNotifier<Map<int, TrackedUser>> users = ValueNotifier({});

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  bool _shouldConnect = false;

  IndoorTrackingWsClient(this.floorId);

  void start() {
    _shouldConnect = true;
    _connect();
  }

  void stop() {
    _shouldConnect = false;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  void _connect() {
    if (!_shouldConnect || _channel != null) return;
    final token = NetworkManager.instance.token;
    if (token == null) return;

    try {
      final uri = Uri.parse(ApiRoutes.indoorTrackingWs(floorId));
      _channel = WebSocketChannel.connect(uri);
      // JWT as the first message, not a URL query param - see
      // ApiRoutes.indoorTrackingWs's comment / backend/services/ws_auth.py.
      // This socket streams live physical locations, so keeping the token
      // out of the URL (proxy/access logs, browser history) matters even
      // more here than on the call-signaling socket.
      _channel!.sink.add(jsonEncode({'type': 'auth', 'token': token}));
      _sub = _channel!.stream.listen((data) {
        try {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          final type = msg['type'] as String?;
          final payload = msg['data'] as Map<String, dynamic>?;
          if (payload == null) return;
          final user = TrackedUser.fromJson(payload);

          final next = Map<int, TrackedUser>.from(users.value);
          if (type == 'session_stopped') {
            next.remove(user.attendanceSessionId);
          } else if (type == 'session_left_floor') {
            next.remove(user.attendanceSessionId);
          } else {
            next[user.attendanceSessionId] = user;
          }
          next.removeWhere(
              (_, tracked) => DateTime.now().difference(tracked.updatedAt) > _maxTrackedAge);
          users.value = next;
        } catch (e) {
          debugPrint('[IndoorTrackingWs] parse error: $e');
        }
      }, onError: (_) => _scheduleReconnect(), onDone: () => _scheduleReconnect());
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _sub?.cancel();
    _channel = null;
    if (!_shouldConnect) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), _connect);
  }
}
