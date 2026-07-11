import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../network/api_routes.dart';

class GlobalCameraStatus {
  static final ValueNotifier<Map<int, bool>> statuses = ValueNotifier({});
  static WebSocketChannel? _channel;
  static StreamSubscription? _sub;
  static Timer? _reconnectTimer;
  static bool _shouldBePolling = false;

  static void startPolling() {
    _shouldBePolling = true;
    _connectWs();
  }

  static void stopPolling() {
    _shouldBePolling = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _disconnectWs();
  }

  static void _connectWs() {
    if (!_shouldBePolling) return;
    if (_channel != null) return;

    try {
      final wsUri = Uri.parse(ApiRoutes.camerasStatusWs);
      _channel = WebSocketChannel.connect(wsUri);

      _sub = _channel!.stream.listen((data) {
        try {
          final Map<String, dynamic> decoded = jsonDecode(data as String);
          final newMap = decoded
              .map((key, value) => MapEntry(int.parse(key), value as bool));
          if (!mapEquals(statuses.value, newMap)) {
            statuses.value = newMap;
          }
        } catch (e) {
          debugPrint("Error parsing camera status ws: $e");
        }
      }, onError: (e) {
        _scheduleReconnect();
      }, onDone: () {
        _scheduleReconnect();
      });
    } catch (e) {
      _scheduleReconnect();
    }
  }

  static void _disconnectWs() {
    _sub?.cancel();
    _channel?.sink.close();
    _sub = null;
    _channel = null;
  }

  static void _scheduleReconnect() {
    _disconnectWs();
    if (!_shouldBePolling) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      _connectWs();
    });
  }
}
