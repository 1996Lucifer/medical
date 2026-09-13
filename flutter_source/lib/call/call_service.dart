import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../network/api_routes.dart';
import 'call_models.dart';

/// Manages the call-signaling WebSocket and the WebRTC peer connection for
/// one call at a time. One instance lives for the whole app session (see
/// main.dart), auto-connecting once the user is authenticated, so an
/// incoming call can ring regardless of which screen is currently open.
///
/// Signaling protocol (relayed as-is by backend/routers/calls.py, which
/// only inspects `type`/`action`/`to` to route and authorize - everything
/// else is opaque to it):
///   {"type":"call","action":"invite"|"accept"|"reject"|"hangup"|
///                          "unavailable"|"denied","to":<id>,"from":<id>,
///    "mode":"audio"|"video","peer_name":"..."}
///   {"type":"signal","kind":"offer"|"answer"|"ice","to":<id>,"from":<id>,
///    "payload":{...}}
class CallService extends ChangeNotifier {
  WebSocketChannel? _channel;
  int? _myUserId;
  String _myName = '';
  RTCPeerConnection? _pc;

  CallState callState = CallState.idle;
  CallMode? mode;
  CallPeer? peer;
  String? lastError;

  MediaStream? localStream;
  MediaStream? remoteStream;
  bool micEnabled = true;
  bool cameraEnabled = true;

  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      // Free public TURN (openrelay.metered.ca) - fine for getting calls
      // working across networks during development; swap for a dedicated
      // TURN server before relying on this for real production traffic.
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
  };

  bool get isConnected => _channel != null;

  void connect(int myUserId, String token, {String myName = ''}) {
    if (_channel != null && _myUserId == myUserId) return;
    disconnect();
    _myUserId = myUserId;
    _myName = myName;
    try {
      _channel = WebSocketChannel.connect(Uri.parse(ApiRoutes.callsWs(token)));
      _channel!.stream.listen(
        _onMessage,
        onDone: () {
          _channel = null;
          // Auto-reconnect after a short delay if we still think we should
          // be connected (e.g. transient network drop, not an explicit
          // disconnect()).
          if (_myUserId == myUserId) {
            Future.delayed(const Duration(seconds: 3), () {
              if (_myUserId == myUserId) connect(myUserId, token, myName: myName);
            });
          }
        },
        onError: (_) {},
      );
    } catch (e) {
      lastError = 'Failed to connect call signaling: $e';
      notifyListeners();
    }
  }

  void disconnect() {
    _myUserId = null;
    _channel?.sink.close();
    _channel = null;
  }

  void _send(Map<String, dynamic> envelope) {
    _channel?.sink.add(jsonEncode(envelope));
  }

  void _onMessage(dynamic raw) {
    Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final type = envelope['type'];
    if (type == 'call') {
      _handleCallEnvelope(envelope);
    } else if (type == 'signal') {
      _handleSignalEnvelope(envelope);
    }
  }

  void _handleCallEnvelope(Map<String, dynamic> envelope) {
    final action = envelope['action'];
    switch (action) {
      case 'invite':
        if (callState != CallState.idle) {
          // Busy - let the caller know rather than silently dropping it.
          _send({'type': 'call', 'action': 'reject', 'to': envelope['from']});
          return;
        }
        peer = CallPeer(
          userId: envelope['from'],
          name: envelope['peer_name']?.toString() ?? 'Unknown',
        );
        mode = envelope['mode'] == 'video' ? CallMode.video : CallMode.audio;
        callState = CallState.ringingIncoming;
        notifyListeners();
        break;

      case 'accept':
        if (callState == CallState.ringingOutgoing) {
          _createOfferAsCaller();
        }
        break;

      case 'reject':
      case 'hangup':
      case 'unavailable':
      case 'denied':
        if (action == 'denied') lastError = envelope['reason']?.toString();
        _teardown();
        callState = CallState.ended;
        notifyListeners();
        break;
    }
  }

  Future<void> _handleSignalEnvelope(Map<String, dynamic> envelope) async {
    if (_pc == null) return;
    final kind = envelope['kind'];
    final payload = envelope['payload'] as Map<String, dynamic>?;
    if (payload == null) return;

    try {
      if (kind == 'offer') {
        await _pc!.setRemoteDescription(
          RTCSessionDescription(payload['sdp'], payload['type']),
        );
        final answer = await _pc!.createAnswer();
        await _pc!.setLocalDescription(answer);
        _send({
          'type': 'signal',
          'kind': 'answer',
          'to': peer!.userId,
          'payload': {'sdp': answer.sdp, 'type': answer.type},
        });
      } else if (kind == 'answer') {
        await _pc!.setRemoteDescription(
          RTCSessionDescription(payload['sdp'], payload['type']),
        );
      } else if (kind == 'ice') {
        await _pc!.addCandidate(RTCIceCandidate(
          payload['candidate'],
          payload['sdpMid'],
          payload['sdpMLineIndex'],
        ));
      }
    } catch (e) {
      debugPrint('[CallService] Signal handling error: $e');
    }
  }

  /// Caller side: rings a peer. Doesn't touch camera/mic until the callee
  /// actually accepts (see _createOfferAsCaller), so a declined/unanswered
  /// call never grabs media.
  void startCall(CallPeer target, CallMode callMode) {
    if (callState != CallState.idle) return;
    peer = target;
    mode = callMode;
    callState = CallState.ringingOutgoing;
    notifyListeners();
    _send({
      'type': 'call',
      'action': 'invite',
      'to': target.userId,
      'mode': callMode == CallMode.video ? 'video' : 'audio',
      'peer_name': _myName,
    });
  }

  Future<void> acceptIncomingCall() async {
    if (callState != CallState.ringingIncoming || peer == null) return;
    callState = CallState.connecting;
    notifyListeners();
    try {
      await _setupPeerConnection();
      _send({'type': 'call', 'action': 'accept', 'to': peer!.userId});
    } catch (e) {
      lastError = 'Failed to access camera/microphone: $e';
      _teardown();
      callState = CallState.ended;
      notifyListeners();
    }
  }

  void rejectIncomingCall() {
    if (peer != null) {
      _send({'type': 'call', 'action': 'reject', 'to': peer!.userId});
    }
    _teardown();
    callState = CallState.idle;
    notifyListeners();
  }

  void hangUp() {
    if (peer != null) {
      _send({'type': 'call', 'action': 'hangup', 'to': peer!.userId});
    }
    _teardown();
    callState = CallState.ended;
    notifyListeners();
  }

  /// Called by the UI once it's shown the "call ended" state briefly.
  void resetToIdle() {
    callState = CallState.idle;
    peer = null;
    mode = null;
    lastError = null;
    notifyListeners();
  }

  Future<void> _createOfferAsCaller() async {
    callState = CallState.connecting;
    notifyListeners();
    try {
      await _setupPeerConnection();
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      _send({
        'type': 'signal',
        'kind': 'offer',
        'to': peer!.userId,
        'payload': {'sdp': offer.sdp, 'type': offer.type},
      });
    } catch (e) {
      lastError = 'Failed to access camera/microphone: $e';
      _teardown();
      callState = CallState.ended;
      notifyListeners();
    }
  }

  Future<void> _setupPeerConnection() async {
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': mode == CallMode.video
          ? {'facingMode': 'user'}
          : false,
    });

    _pc = await createPeerConnection(_iceServers);

    for (final track in localStream!.getTracks()) {
      await _pc!.addTrack(track, localStream!);
    }

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteStream = event.streams[0];
        notifyListeners();
      }
    };

    _pc!.onIceCandidate = (candidate) {
      if (peer == null) return;
      _send({
        'type': 'signal',
        'kind': 'ice',
        'to': peer!.userId,
        'payload': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    _pc!.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        if (callState == CallState.connecting) {
          callState = CallState.active;
          notifyListeners();
        }
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        if (callState == CallState.active || callState == CallState.connecting) {
          _teardown();
          callState = CallState.ended;
          notifyListeners();
        }
      }
    };

    notifyListeners();
  }

  void toggleMic() {
    micEnabled = !micEnabled;
    localStream?.getAudioTracks().forEach((t) => t.enabled = micEnabled);
    notifyListeners();
  }

  void toggleCamera() {
    cameraEnabled = !cameraEnabled;
    localStream?.getVideoTracks().forEach((t) => t.enabled = cameraEnabled);
    notifyListeners();
  }

  void _teardown() {
    for (final track in localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      track.stop();
    }
    localStream?.dispose();
    localStream = null;
    remoteStream = null;
    _pc?.close();
    _pc = null;
    peer = null;
    mode = null;
    micEnabled = true;
    cameraEnabled = true;
  }

  @override
  void dispose() {
    _teardown();
    disconnect();
    super.dispose();
  }
}
