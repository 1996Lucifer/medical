import 'dart:convert';

import 'api_routes.dart';
import 'network_manager.dart';

/// A registered physical RFID device (writer/enrollment or reader/
/// verification terminal) — see routers/rfid.py.
class RfidDevice {
  final int id;
  final String label;
  final bool isActive;
  final DateTime? lastSeenAt;

  RfidDevice({
    required this.id,
    required this.label,
    required this.isActive,
    this.lastSeenAt,
  });

  factory RfidDevice.fromJson(Map<String, dynamic> j) => RfidDevice(
        id: j['id'],
        label: j['label'],
        isActive: j['is_active'] ?? true,
        lastSeenAt: j['last_seen_at'] != null
            ? DateTime.parse(j['last_seen_at'])
            : null,
      );
}

/// Thin wrapper around the /api/rfid/* endpoints, following the same
/// shape as network/admin_dashboard_service.dart.
class RfidService {
  Future<List<RfidDevice>> fetchDevices() async {
    final resp = await NetworkManager.instance.get(ApiRoutes.rfidDevices);
    if (resp.statusCode == 200) {
      return (jsonDecode(resp.body) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(RfidDevice.fromJson)
          .toList();
    }
    throw Exception('Failed to load RFID devices: ${resp.statusCode}');
  }

  /// Registers a new device. Returns the raw `device_key` — shown to the
  /// admin exactly once, never retrievable again.
  Future<Map<String, dynamic>> registerDevice(String label) async {
    final resp = await NetworkManager.instance.post(
      ApiRoutes.rfidDevices,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'label': label}),
    );
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to register device: ${resp.statusCode}');
  }

  /// Opens a 90s enroll window binding the next card tapped on
  /// [deviceId] to [staffId]. Returns {session_id, expires_at}.
  Future<Map<String, dynamic>> createEnrollSession({
    required int deviceId,
    required int staffId,
  }) async {
    final resp = await NetworkManager.instance.post(
      ApiRoutes.rfidEnrollSessions,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'device_id': deviceId, 'staff_id': staffId}),
    );
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to start enroll session: ${resp.statusCode}');
  }

  /// Polls whether a card has been tapped yet. Returns {consumed, expired}.
  Future<Map<String, dynamic>> getEnrollSessionStatus(int sessionId) async {
    final resp = await NetworkManager.instance
        .get(ApiRoutes.rfidEnrollSessionStatus(sessionId));
    if (resp.statusCode == 200) {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to poll enroll session: ${resp.statusCode}');
  }

  /// Remotely resets the fixed station's WiFi/backend config and restarts
  /// it into its setup portal - the backend calls the device directly over
  /// the LAN using RFID_STATION_DEVICE_KEY/_IP from its own .env, so the
  /// raw device key never passes through this app (see
  /// routers/rfid.py's reset_station_config).
  Future<void> resetStationConfig() async {
    final resp = await NetworkManager.instance.post(
      ApiRoutes.rfidStationResetConfig,
      headers: {'Content-Type': 'application/json'},
      body: '{}',
    );
    if (resp.statusCode == 200) return;
    final detail = () {
      try {
        return (jsonDecode(resp.body) as Map<String, dynamic>)['detail'];
      } catch (_) {
        return resp.body;
      }
    }();
    throw Exception('Failed to reset station: $detail');
  }
}
