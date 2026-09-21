import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../network/api_routes.dart';
import '../network/network_manager.dart';
import 'call_models.dart';
import 'call_notification_service.dart';
import 'call_sound_service.dart';

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
  DateTime _callStateSince = DateTime.now();
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
    // Without this, which platform/browser combo defaults to plan-b vs
    // unified-plan SDP semantics is left unspecified - a real, known
    // cross-platform interop gap where audio negotiates fine but a video
    // m-line can end up rejected/inactive on one side. Pin both ends to the
    // same semantics explicitly instead of relying on matching defaults.
    'sdpSemantics': 'unified-plan',
  };

  bool get isConnected => _channel != null;

  void connect(int myUserId, String token, {String myName = ''}) {
    if (_channel != null && _myUserId == myUserId) return;
    disconnect();
    _myUserId = myUserId;
    _myName = myName;
    // WebSocketChannel.connect() does not await the handshake - it returns
    // immediately and any failure (wrong host, refused, timeout) only ever
    // surfaces later through the stream's onError/onDone, never as a thrown
    // exception here. Discovered live: onError was a no-op ((_) {}), so a
    // failed handshake was silently swallowed - no log, no lastError, and
    // critically no reconnect attempt (only onDone scheduled one). If the
    // very first connection attempt ever failed for any reason, the app was
    // permanently stuck with no signaling connection and zero indication
    // why - indistinguishable from every incoming call just never arriving.
    void scheduleReconnect() {
      if (_myUserId == myUserId) {
        Future.delayed(const Duration(seconds: 3), () {
          if (_myUserId == myUserId) connect(myUserId, token, myName: myName);
        });
      }
    }

    try {
      _channel = WebSocketChannel.connect(Uri.parse(ApiRoutes.callsWs));
      // The JWT is the first message on the socket, not a URL query param
      // (see ApiRoutes.callsWs's comment / backend/services/ws_auth.py) -
      // sent immediately so the server's short auth window doesn't expire
      // before any other envelope would ever be sent.
      _channel!.sink.add(jsonEncode({'type': 'auth', 'token': token}));
      _channel!.stream.listen(
        _onMessage,
        onDone: () {
          _channel = null;
          scheduleReconnect();
        },
        onError: (Object e) {
          debugPrint('[CallService] Signaling connection error: $e');
          lastError = 'Call signaling connection failed: $e';
          _channel = null;
          notifyListeners();
          scheduleReconnect();
        },
      );
    } catch (e) {
      lastError = 'Failed to connect call signaling: $e';
      notifyListeners();
      scheduleReconnect();
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

  void _setCallState(CallState state) {
    callState = state;
    _callStateSince = DateTime.now();
  }

  /// Discovered live: a connection kick (two sockets briefly registering as
  /// the same account - e.g. testing the same login on two devices at
  /// once), an interrupted media/PC setup, or any other edge case that
  /// leaves callState stuck at something other than idle with no CallScreen
  /// mounted to ever drive it back to idle, permanently and silently
  /// rejects every future incoming call with zero indication why - "picking
  /// up" looks broken forever until the app is fully restarted. Since a
  /// real call reaches CallState.active within seconds of ringing/dialing,
  /// treating a long-stuck non-idle state as stale and self-healing back to
  /// idle is a safe backstop: a call that's actually still legitimately in
  /// progress will have already reached `active` well before this fires.
  static const _staleCallStateThreshold = Duration(seconds: 45);

  bool get _isStaleNonIdle =>
      callState != CallState.idle &&
      DateTime.now().difference(_callStateSince) > _staleCallStateThreshold;

  /// Test-only hook: backdates the last call-state transition so staleness
  /// recovery can be exercised without a real 45-second wait.
  @visibleForTesting
  void debugBackdateCallState(Duration age) {
    _callStateSince = DateTime.now().subtract(age);
  }

  /// Test-only hook: feeds a signaling envelope through the same path a
  /// real WebSocket message takes, without needing a live connection.
  @visibleForTesting
  void debugHandleEnvelope(Map<String, dynamic> envelope) {
    _onMessage(jsonEncode(envelope));
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
    } else if (type == 'message') {
      _handleMessageEnvelope(envelope);
    }
  }

  // ---------------------------------------------------------------------
  // Chat messaging - persisted server-side (backend/models.py's
  // StaffMessage, routers/messages.py), not just an in-memory envelope on
  // this WebSocket. Originally this was purely "send an envelope over the
  // call-signaling socket and hope the other side is connected" - a
  // message to an offline recipient was silently dropped with no trace it
  // was ever sent, and all history vanished on every app restart. Sending
  // now POSTs to the backend (which persists first, then best-effort
  // pushes a live envelope if the peer happens to be connected); the
  // WebSocket path below only ever handles that live-push side, never the
  // sole record of a message.
  // ---------------------------------------------------------------------

  final Map<int, List<ChatMessage>> _messagesByPeer = {};
  final Map<int, int> _unreadCountByPeer = {};

  // Caps how much per-peer message history is kept in memory for the whole
  // app session - without this, _messagesByPeer grows unbounded for the
  // lifetime of the app. Unread counts are tracked separately in
  // _unreadCountByPeer and are never trimmed, so this only affects how much
  // scroll-back history is available without a fresh loadHistory() call.
  static const _maxHistoryPerPeer = 200;

  /// Trims [peerId]'s message history to the most recent [_maxHistoryPerPeer]
  /// messages, dropping the oldest first.
  void _trimHistory(int peerId) {
    final history = _messagesByPeer[peerId];
    if (history != null && history.length > _maxHistoryPerPeer) {
      history.removeRange(0, history.length - _maxHistoryPerPeer);
    }
  }

  List<ChatMessage> messagesWith(int peerId) =>
      List.unmodifiable(_messagesByPeer[peerId] ?? const []);

  int unreadCountFor(int peerId) => _unreadCountByPeer[peerId] ?? 0;

  int get totalUnreadCount =>
      _unreadCountByPeer.values.fold(0, (sum, count) => sum + count);

  /// Loads persisted history for one conversation - called when a chat
  /// screen opens, since the in-memory map above only ever holds what's
  /// arrived live since app launch.
  Future<void> loadHistory(int peerId) async {
    if (_myUserId == null) return;
    try {
      final response =
          await NetworkManager.instance.get(ApiRoutes.messagesWith(peerId));
      if (response.statusCode != 200) return;
      final rows = jsonDecode(response.body) as List<dynamic>;
      _messagesByPeer[peerId] = rows
          .map((row) => ChatMessage.fromJson(
                row as Map<String, dynamic>,
                myUserId: _myUserId!,
              ))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('[CallService] Failed to load message history for $peerId: $e');
    }
  }

  /// Loads the conversations list (one row per peer, with unread counts) -
  /// what the People Directory's per-contact message badge is fed from.
  Future<List<ConversationSummary>> loadConversations() async {
    try {
      final response =
          await NetworkManager.instance.get(ApiRoutes.messageConversations);
      if (response.statusCode != 200) return const [];
      final rows = jsonDecode(response.body) as List<dynamic>;
      final summaries = rows
          .map((row) =>
              ConversationSummary.fromJson(row as Map<String, dynamic>))
          .toList();
      _unreadCountByPeer
        ..clear()
        ..addEntries(summaries
            .where((s) => s.unreadCount > 0)
            .map((s) => MapEntry(s.peerId, s.unreadCount)));
      notifyListeners();
      return summaries;
    } catch (e) {
      debugPrint('[CallService] Failed to load conversations: $e');
      return const [];
    }
  }

  /// Loads recent call history (GET /api/calls/log) - what the Inbox
  /// screen's "Calls" tab shows so a missed/unavailable call from someone
  /// outside the People Directory (no Staff row) isn't just lost the
  /// moment the ringing stops.
  Future<List<CallLogEntry>> loadCallLog() async {
    try {
      final response = await NetworkManager.instance.get(ApiRoutes.callLog);
      if (response.statusCode != 200) return const [];
      final rows = jsonDecode(response.body) as List<dynamic>;
      return rows
          .map((row) => CallLogEntry.fromJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[CallService] Failed to load call log: $e');
      return const [];
    }
  }

  /// Sends a message. Appended to the local list immediately (optimistic,
  /// for a responsive chat UI) - the POST persists it server-side and
  /// best-effort pushes it live to the peer if they're connected.
  Future<void> sendMessage(int peerId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _messagesByPeer
        .putIfAbsent(peerId, () => [])
        .add(ChatMessage(peerId: peerId, text: trimmed, isMine: true, timestamp: DateTime.now()));
    _trimHistory(peerId);
    notifyListeners();
    try {
      final response = await NetworkManager.instance.post(
        ApiRoutes.sendMessage,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'to': peerId, 'text': trimmed}),
      );
      if (response.statusCode != 200) {
        lastError = 'Failed to send message (${response.statusCode})';
        notifyListeners();
      }
    } catch (e) {
      lastError = 'Failed to send message: $e';
      notifyListeners();
    }
  }

  /// Marks every message from [peerId] as read, both server-side and in
  /// this session's unread badge count.
  Future<void> markRead(int peerId) async {
    if (_unreadCountByPeer.remove(peerId) != null) notifyListeners();
    try {
      await NetworkManager.instance.post(ApiRoutes.markMessagesRead(peerId));
    } catch (e) {
      debugPrint('[CallService] Failed to mark messages read for $peerId: $e');
    }
  }

  /// Live push from routers/messages.py's send_message() when this device
  /// is connected at the moment a peer sends a message - purely a
  /// same-session convenience so an already-open chat updates instantly;
  /// loadHistory() above is what actually guarantees a message is seen.
  void _handleMessageEnvelope(Map<String, dynamic> envelope) {
    final fromId = envelope['from'];
    final text = envelope['text'];
    if (fromId is! int || text is! String) return;
    final id = envelope['id'] as int?;
    final createdAt = envelope['created_at'] as String?;
    _messagesByPeer.putIfAbsent(fromId, () => []).add(ChatMessage(
          id: id,
          peerId: fromId,
          text: text,
          isMine: false,
          timestamp: createdAt != null ? DateTime.parse(createdAt) : DateTime.now(),
        ));
    _trimHistory(fromId);
    _unreadCountByPeer[fromId] = (_unreadCountByPeer[fromId] ?? 0) + 1;
    notifyListeners();
  }

  void _handleCallEnvelope(Map<String, dynamic> envelope) {
    final action = envelope['action'];
    switch (action) {
      case 'invite':
        if (callState != CallState.idle && !_isStaleNonIdle) {
          // Busy - let the caller know rather than silently dropping it.
          _send({'type': 'call', 'action': 'reject', 'to': envelope['from']});
          return;
        }
        if (callState != CallState.idle) {
          // Stale lockout recovered - see _isStaleNonIdle.
          debugPrint('[CallService] Clearing stale callState=$callState before accepting new invite');
          _teardown();
        }
        peer = CallPeer(
          userId: envelope['from'],
          name: envelope['peer_name']?.toString() ?? 'Unknown',
        );
        mode = envelope['mode'] == 'video' ? CallMode.video : CallMode.audio;
        _setCallState(CallState.ringingIncoming);
        CallSoundService().startRinging();
        CallNotificationService().showIncomingCall(
          callerName: peer!.name,
          isVideo: mode == CallMode.video,
        );
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
        // Covers both "they hung up before we picked up" (still ringing)
        // and "they hung up on an active call" - stopRinging() is a no-op
        // when nothing is ringing, so unconditional is safe here.
        CallSoundService().stopRinging();
        CallNotificationService().clearIncomingCall();
        CallSoundService().playEnded();
        _teardown();
        _setCallState(CallState.ended);
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
    if (callState != CallState.idle) {
      if (!_isStaleNonIdle) return;
      debugPrint('[CallService] Clearing stale callState=$callState before starting a new call');
      _teardown();
    }
    peer = target;
    mode = callMode;
    _setCallState(CallState.ringingOutgoing);
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
    CallSoundService().stopRinging();
    CallNotificationService().clearIncomingCall();
    _setCallState(CallState.connecting);
    notifyListeners();
    try {
      await _setupPeerConnection();
      _send({'type': 'call', 'action': 'accept', 'to': peer!.userId});
    } catch (e) {
      lastError = 'Failed to access camera/microphone: $e';
      CallSoundService().playEnded();
      _teardown();
      _setCallState(CallState.ended);
      notifyListeners();
    }
  }

  void rejectIncomingCall() {
    CallSoundService().stopRinging();
    CallNotificationService().clearIncomingCall();
    if (peer != null) {
      _send({'type': 'call', 'action': 'reject', 'to': peer!.userId});
    }
    _teardown();
    _setCallState(CallState.idle);
    notifyListeners();
  }

  void hangUp() {
    if (peer != null) {
      _send({'type': 'call', 'action': 'hangup', 'to': peer!.userId});
    }
    CallSoundService().playEnded();
    _teardown();
    _setCallState(CallState.ended);
    notifyListeners();
  }

  /// Called by the UI once it's shown the "call ended" state briefly.
  void resetToIdle() {
    _setCallState(CallState.idle);
    peer = null;
    mode = null;
    lastError = null;
    notifyListeners();
  }

  Future<void> _createOfferAsCaller() async {
    _setCallState(CallState.connecting);
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
      CallSoundService().playEnded();
      _teardown();
      _setCallState(CallState.ended);
      notifyListeners();
    }
  }

  Future<void> _setupPeerConnection() async {
    // A slow/unanswered OS permission prompt (or a stuck device/driver) can
    // leave getUserMedia() pending indefinitely - discovered live: a callee
    // stuck here has no way to dismiss the incoming-call screen, and the
    // caller hanging up in the meantime doesn't help either, since this
    // await never resolves to let the surrounding catch block run. A
    // timeout guarantees it eventually fails and hits the existing
    // catch-and-teardown path in acceptIncomingCall()/_createOfferAsCaller()
    // instead of hanging the call forever.
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': mode == CallMode.video
          ? {'facingMode': 'user'}
          : false,
    }).timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw Exception('Timed out waiting for camera/microphone access'),
    );

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
          _setCallState(CallState.active);
          CallSoundService().playConnected();
          notifyListeners();
        }
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        if (callState == CallState.active || callState == CallState.connecting) {
          CallSoundService().playEnded();
          _teardown();
          _setCallState(CallState.ended);
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
