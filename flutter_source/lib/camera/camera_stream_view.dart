import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

import '../network/api_routes.dart';

class CameraStreamView extends StatefulWidget {
  final int cameraId;
  final BoxFit fit;
  final String mode;

  const CameraStreamView({
    super.key,
    required this.cameraId,
    this.fit = BoxFit.contain,
    this.mode = 'ai',
  });

  @override
  State<CameraStreamView> createState() => _CameraStreamViewState();
}

class _CameraStreamViewState extends State<CameraStreamView> {
  RTCPeerConnection? _peerConnection;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  bool _isConnected = false;
  String? _errorMessage;
  Timer? _reconnectTimer;

  @override
  void initState() {
    super.initState();
    _initRenderer();
    _connectWebRTC();
  }

  Future<void> _initRenderer() async {
    await _localRenderer.initialize();
  }

  @override
  void didUpdateWidget(CameraStreamView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cameraId != widget.cameraId ||
        oldWidget.mode != widget.mode) {
      _reconnectTimer?.cancel();
      _disconnect();
      _connectWebRTC();
    }
  }

  Future<void> _connectWebRTC() async {
    setState(() {
      _errorMessage = null;
    });

    try {
      _peerConnection = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'}
        ],
      });

      _peerConnection?.onTrack = (event) {
        if (event.track.kind == 'video') {
          _localRenderer.srcObject = event.streams[0];
          setState(() => _isConnected = true);
        }
      };

      _peerConnection?.onIceConnectionState = (state) {
        if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          _scheduleReconnect();
        }
      };

      // We must add a transceiver to receive video
      await _peerConnection?.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );

      RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      final response = await http.post(
        Uri.parse(ApiRoutes.webrtcOffer(widget.cameraId,
            mode: 'webrtc_${widget.mode}')),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'sdp': offer.sdp, 'type': offer.type}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        RTCSessionDescription answer =
            RTCSessionDescription(data['sdp'], data['type']);
        await _peerConnection!.setRemoteDescription(answer);
      } else {
        throw Exception('Failed to connect to WebRTC backend');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isConnected = false;
        });
        _scheduleReconnect();
      }
    }
  }

  /// A dead/unreachable backend or a bad network previously caused a
  /// tight reconnect loop here (onIceConnectionState firing
  /// Disconnected/Failed -> immediate _connectWebRTC() -> fails again ->
  /// immediate retry...), churning CPU/battery/data with no delay. One
  /// pending timer at a time, same fixed-delay convention this app
  /// already uses for its other reconnecting sockets (e.g.
  /// camera_status_service.dart's GlobalCameraStatus).
  void _scheduleReconnect() {
    if (!mounted) return;
    _disconnect();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _connectWebRTC();
    });
  }

  Future<void> _disconnect() async {
    await _peerConnection?.close();
    _peerConnection = null;
    _localRenderer.srcObject = null;
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _disconnect();
    _localRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Center(
        child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
      );
    }
    if (_isConnected) {
      return RTCVideoView(
        _localRenderer,
        objectFit: widget.fit == BoxFit.cover
            ? RTCVideoViewObjectFit.RTCVideoViewObjectFitCover
            : RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
      );
    }
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Connecting WebRTC...', style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}
