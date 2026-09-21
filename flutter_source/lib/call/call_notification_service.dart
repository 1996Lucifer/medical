import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Raises a native OS notification for an incoming call.
///
/// The in-app IncomingCallOverlay only ever gets a chance to paint while the
/// app/tab is actually visible - a backgrounded app or hidden browser tab
/// means a call can arrive correctly (CallService gets the invite, the
/// ringtone starts) with nothing on-screen ever indicating it. Ported from
/// kram's frontend-v2 NotificationService, which exists for the exact same
/// reason.
class CallNotificationService {
  static final CallNotificationService _instance = CallNotificationService._internal();
  factory CallNotificationService() => _instance;
  CallNotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  /// On web, `_plugin.initialize()` registers a service worker
  /// (notifications_service_worker.js) - found live: doing that
  /// unconditionally at app cold boot (main.dart, before login, before any
  /// user interaction) reliably threw "An unknown error occurred when
  /// fetching the script" in the console on every load. It was already
  /// caught and non-fatal, but noisy on every single session regardless of
  /// whether that user ever receives a call. Deferring the actual
  /// `_plugin.initialize()` call to the moment a notification is first
  /// needed (showIncomingCall, well after login/interaction) both avoids
  /// paying that cost for the common case of a session with no incoming
  /// call, and gives the browser a far more normal, already-interactive
  /// page state to register against. Native platforms keep eager init -
  /// there's no cold-boot race there, and it's what requests OS permission
  /// prompts up front as before.
  Future<void> init() async {
    if (kIsWeb) return;
    await _ensureInitialized();
  }

  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;

    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
        macOS: iosSettings,
      );

      await _plugin.initialize(settings: initSettings);

      if (!kIsWeb) {
        final iosImpl = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        await iosImpl?.requestPermissions(alert: true, badge: true, sound: true);

        const channel = AndroidNotificationChannel(
          'calls_channel',
          'Incoming Calls',
          description: 'Alerts for incoming audio/video calls',
          importance: Importance.max,
          enableVibration: true,
          playSound: true,
        );
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel);
      }

      _isInitialized = true;
    } catch (e) {
      debugPrint('CallNotificationService: init failed: $e');
    }
  }

  Future<void> showIncomingCall({required String callerName, required bool isVideo}) async {
    if (!_isInitialized) await _ensureInitialized();
    if (!_isInitialized) return;
    try {
      const androidDetails = AndroidNotificationDetails(
        'calls_channel',
        'Incoming Calls',
        channelDescription: 'Alerts for incoming audio/video calls',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.call,
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      );
      await _plugin.show(
        id: 0,
        title: isVideo ? 'Incoming video call' : 'Incoming call',
        body: '$callerName is calling you now',
        notificationDetails: const NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
          macOS: iosDetails,
        ),
      );
    } catch (e) {
      debugPrint('CallNotificationService: showIncomingCall failed: $e');
    }
  }

  /// Clears the incoming-call notification once it stops being relevant
  /// (answered, declined, the caller hung up before pickup).
  Future<void> clearIncomingCall() async {
    try {
      await _plugin.cancel(id: 0);
    } catch (e) {
      debugPrint('CallNotificationService: clearIncomingCall failed: $e');
    }
  }
}
