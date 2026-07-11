import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../network/api_routes.dart';

class CameraStreamView extends StatefulWidget {
  final int cameraId;
  final BoxFit fit;
  final String mode;

  const CameraStreamView(
      {super.key,
      required this.cameraId,
      this.fit = BoxFit.contain,
      this.mode = 'ai'});

  @override
  State<CameraStreamView> createState() => _CameraStreamViewState();
}

class _CameraStreamViewState extends State<CameraStreamView> {
  bool _isConnected = false;
  bool _isConnecting = true;
  Uint8List? _frameBytes;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  String? _errorMessage;
  Timer? _reconnectTimer;
  String? _lastDisconnectReason;

  @override
  void initState() {
    super.initState();
    print('CameraStreamView INIT: ${widget.cameraId}');
    _connectStream();
  }

  @override
  void didUpdateWidget(CameraStreamView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cameraId != widget.cameraId ||
        oldWidget.mode != widget.mode) {
      _disconnect();
      _connectStream();
    }
  }

  Future<void> _connectStream() async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
      _lastDisconnectReason = null;
    });

    final wsUri =
        Uri.parse(ApiRoutes.cameraWs(widget.cameraId, mode: widget.mode));
    try {
      _channel = WebSocketChannel.connect(wsUri);
      await _channel!.ready;
      if (!mounted) return;
      setState(() {
        _isConnected = true;
      });
      _sub = _channel!.stream.listen(
        (data) {
          if (mounted) {
            setState(() {
              _isConnecting = false;
              try {
                _frameBytes = data is Uint8List
                    ? data
                    : Uint8List.fromList(data as List<int>);
              } catch (e) {
                _lastDisconnectReason = "Data cast error: $e";
              }
            });
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _errorMessage = 'Error: $e';
              _lastDisconnectReason = 'Error: $e';
              _isConnected = false;
              _isConnecting = false;
            });
            _scheduleReconnect();
          }
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _lastDisconnectReason =
                  'onDone called. Close code: ${_channel?.closeCode}, reason: ${_channel?.closeReason}';
              _isConnected = false;
              _isConnecting = false;
            });
            _scheduleReconnect();
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _errorMessage = 'Could not connect: $e';
          _lastDisconnectReason = 'Connect catch: $e';
        });
        _scheduleReconnect();
      }
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (!mounted) return;
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        _disconnect();
        _connectStream();
      }
    });
  }

  Future<void> _disconnect() async {
    _reconnectTimer?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close();
    _sub = null;
    _channel = null;
    if (mounted) {
      setState(() {
        _isConnected = false;
        _frameBytes = null;
      });
    }
  }

  @override
  void dispose() {
    _disconnect();
    print('CameraStreamView DISPOSE: ${widget.cameraId}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child:
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    if (_frameBytes != null) {
      return Image.memory(
        _frameBytes!,
        fit: widget.fit,
        gaplessPlayback: true,
      );
    }
    if (_isConnecting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Connecting to stream...',
                style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          'Stream offline\nReason: ${_lastDisconnectReason ?? "Unknown"}',
          style: const TextStyle(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
