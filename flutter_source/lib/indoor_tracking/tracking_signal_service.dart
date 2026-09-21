import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../network/api_routes.dart';
import '../network/network_manager.dart';

/// Tracking state surfaced to any screen that wants to show the user
/// transparency banner ("indoor location tracking is active..."). Mirrors
/// the ValueNotifier singleton pattern already used by
/// camera/camera_status_service.dart's GlobalCameraStatus.
enum TrackingBannerStatus { inactive, active, pausedOutsideGeofence, stopped }

class TrackingBannerState {
  final TrackingBannerStatus status;
  final DateTime? sessionStartedAt;
  const TrackingBannerState(this.status, this.sessionStartedAt);
}

/// Periodically collects the Wi-Fi/GPS signals the platform actually
/// exposes and posts them to /api/indoor-tracking/signal. The app itself is
/// a valid check-in channel now - the backend opens an attendance session
/// on its own the moment a signal shows real presence (known hospital
/// Wi-Fi, or GPS inside the geofence), so this starts signaling right away
/// rather than waiting to first observe an existing session. A separate,
/// slower poll of /api/attendance/me only fills in the banner's "started
/// at" timestamp (and catches a session opened by face/RFID instead).
/// Battery-conscious: backs off the GPS read frequency, and the signal
/// payload is skipped entirely on a tick where neither reading succeeded.
class TrackingSignalService {
  static final ValueNotifier<TrackingBannerState> banner = ValueNotifier(
    const TrackingBannerState(TrackingBannerStatus.inactive, null),
  );

  static Timer? _sessionPollTimer;
  static Timer? _signalTimer;
  static bool _started = false;
  static int _tick = 0;

  static const _sessionPollInterval = Duration(seconds: 45);
  static const _signalInterval = Duration(seconds: 20);
  // GPS is the battery-costly read (a fresh fix, not just cached radio
  // state like Wi-Fi) and isn't needed every tick while actively tracked
  // and inside the geofence - only Wi-Fi association is. Fetch it every
  // 3rd tick (~60s) normally, but every tick while paused/unknown, since
  // GPS is the only signal that can detect "back inside the geofence" to
  // resume tracking promptly.
  static const _gpsEveryNTicks = 3;

  static void start() {
    if (_started) return;
    _started = true;
    _tick = 0;
    _pollSession();
    _sessionPollTimer = Timer.periodic(_sessionPollInterval, (_) => _pollSession());
    _sendSignal();
    _signalTimer = Timer.periodic(_signalInterval, (_) => _sendSignal());
  }

  static void stop() {
    _started = false;
    _sessionPollTimer?.cancel();
    _signalTimer?.cancel();
    banner.value = const TrackingBannerState(TrackingBannerStatus.inactive, null);
  }

  static Future<void> _pollSession() async {
    try {
      final resp = await NetworkManager.instance.get(ApiRoutes.myAttendanceSession);
      if (resp.statusCode != 200) return;
      final body = resp.body.trim();
      if (body == 'null' || body.isEmpty) {
        banner.value = const TrackingBannerState(TrackingBannerStatus.inactive, null);
        return;
      }
      final data = jsonDecode(body) as Map<String, dynamic>;
      final entryTime = DateTime.tryParse(data['entry_time'] as String? ?? '');
      banner.value = TrackingBannerState(banner.value.status, entryTime);
    } catch (e) {
      debugPrint('[TrackingSignalService] session poll error: $e');
    }
  }

  static Future<void> _sendSignal() async {
    final payload = <String, dynamic>{};

    // Wi-Fi: this is the one signal both iOS and Android can provide -
    // just the currently-connected AP's identity. Neither platform exposes
    // a full nearby-AP scan list without extra entitlements/throttling, so
    // this is intentionally best-effort/single-AP in practice.
    try {
      final info = NetworkInfo();
      final bssid = await info.getWifiBSSID();
      final ssid = await info.getWifiName();
      if (bssid != null && bssid.isNotEmpty) {
        payload['wifi'] = {'bssid': bssid, 'ssid': ssid};
      }
    } catch (e) {
      debugPrint('[TrackingSignalService] wifi read failed: $e');
    }

    // GPS: only if the user granted permission - skip silently otherwise,
    // never prompt repeatedly from a background timer. Throttled to every
    // Nth tick (see _gpsEveryNTicks) unless we're not confirmed active,
    // since GPS is the one signal that detects "back inside the geofence".
    _tick++;
    final paused = banner.value.status != TrackingBannerStatus.active;
    final dueForGps = paused || (_tick % _gpsEveryNTicks == 0);
    if (dueForGps) {
      try {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
          ).timeout(const Duration(seconds: 8));
          payload['gps'] = {
            'lat': pos.latitude,
            'lng': pos.longitude,
            'accuracy_m': pos.accuracy,
          };
        }
      } catch (e) {
        debugPrint('[TrackingSignalService] gps read failed: $e');
      }
    }

    if (!payload.containsKey('wifi') && !payload.containsKey('gps')) {
      return; // nothing to report this tick
    }

    try {
      final resp = await NetworkManager.instance.post(
        ApiRoutes.indoorTrackingSignal,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final status = data['status'] as String? ?? 'not_at_hospital';
        banner.value = TrackingBannerState(_parseStatus(status), banner.value.sessionStartedAt);
      }
    } catch (e) {
      debugPrint('[TrackingSignalService] signal post failed: $e');
    }
  }

  static TrackingBannerStatus _parseStatus(String s) {
    switch (s) {
      case 'paused_outside_geofence':
        return TrackingBannerStatus.pausedOutsideGeofence;
      case 'stopped':
        return TrackingBannerStatus.stopped;
      case 'not_at_hospital':
        return TrackingBannerStatus.inactive;
      default:
        return TrackingBannerStatus.active;
    }
  }

  /// Request the permissions this service actually needs, at a point the
  /// user understands why (e.g. right after a successful login) - never
  /// silently from a background timer.
  static Future<void> requestPermissions() async {
    try {
      await Geolocator.requestPermission();
    } catch (_) {}
  }
}
