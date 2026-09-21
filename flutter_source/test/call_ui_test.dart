import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend/call/call_models.dart';
import 'package:frontend/call/call_service.dart';
import 'package:frontend/call/incoming_call_dialog.dart';

/// Regression tests for two bugs found live in this session:
/// 1. CallService.lastError was set in several places but never displayed -
///    a failed call accept looked exactly like the button doing nothing.
/// 2. call_screen.dart rendered RTCVideoView based only on
///    `remoteStream != null`, never checking for an actual video track -
///    an audio-only remote stream showed a permanent blank video view.
///
/// These don't need a live backend/WebRTC connection - they test the pure
/// UI reaction to CallService state, which is exactly where both bugs were.
void main() {
  // CallService._handleCallEnvelope's 'invite' case fires
  // CallSoundService().startRinging(), which reaches audioplayers'
  // platform channels - unmocked, that throws MissingPluginException
  // asynchronously after the test body's synchronous assertions already
  // ran, misattributing the noise to whatever test happens to run next.
  // These are fire-and-forget calls in production code (never awaited),
  // so a real device/browser genuinely never blocks on them either -
  // mocking the channels here just keeps that same behavior quiet in a
  // test environment that has no real platform to answer them.
  TestWidgetsFlutterBinding.ensureInitialized();
  const globalChannel = MethodChannel('xyz.luan/audioplayers.global');
  const playerChannel = MethodChannel('xyz.luan/audioplayers');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(globalChannel, (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(playerChannel, (call) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(globalChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(playerChannel, null);
  });

  testWidgets(
    'IncomingCallOverlay shows a SnackBar when CallService.lastError is set',
    (tester) async {
      final callService = CallService();

      await tester.pumpWidget(
        ChangeNotifierProvider<CallService>.value(
          value: callService,
          child: const MaterialApp(
            home: Scaffold(body: IncomingCallOverlay()),
          ),
        ),
      );
      await tester.pump();

      // Before the fix, there was no reader of lastError at all - this
      // simulates exactly what acceptIncomingCall()'s catch block does.
      callService.lastError = 'Failed to access camera/microphone: denied';
      callService.notifyListeners();
      await tester.pump(); // process the postFrameCallback
      await tester.pump(); // let the SnackBar animate in

      expect(
        find.text('Failed to access camera/microphone: denied'),
        findsOneWidget,
        reason: 'lastError must be surfaced to the user, not silently dropped',
      );
    },
  );

  testWidgets(
    'IncomingCallOverlay does not show the same error twice for one failure',
    (tester) async {
      final callService = CallService();

      await tester.pumpWidget(
        ChangeNotifierProvider<CallService>.value(
          value: callService,
          child: const MaterialApp(
            home: Scaffold(body: IncomingCallOverlay()),
          ),
        ),
      );
      await tester.pump();

      callService.lastError = 'Call unavailable';
      callService.notifyListeners();
      await tester.pump();
      await tester.pump();

      // An unrelated rebuild (e.g. presence update) must not re-show the
      // same still-set error a second time - only a genuinely NEW error
      // string should trigger a new SnackBar.
      callService.notifyListeners();
      await tester.pump();

      expect(find.text('Call unavailable'), findsOneWidget);
    },
  );

  test(
    'a stale non-idle callState no longer permanently blocks new incoming calls',
    () {
      // Reproduces the real bug found live: a connection kick (two sockets
      // briefly registering as the same account) or an interrupted
      // media/PC setup can leave callState stuck at something other than
      // idle forever, with no CallScreen mounted to ever reset it. Every
      // subsequent incoming call was then silently auto-rejected - "picking
      // up" looked broken with zero indication why, recoverable only by a
      // full app restart.
      final callService = CallService();

      // Simulate a call that got stuck mid-setup (e.g. acceptIncomingCall
      // hung inside _setupPeerConnection).
      callService.debugHandleEnvelope({
        'type': 'call',
        'action': 'invite',
        'from': 99,
        'mode': 'video',
        'peer_name': 'Stuck Caller',
      });
      expect(callService.callState, CallState.ringingIncoming);

      // Backdate it well past the staleness threshold - as if this state
      // has been stuck for a long time with nothing resolving it.
      callService.debugBackdateCallState(const Duration(minutes: 2));

      // A brand new invite arrives from someone else entirely.
      callService.debugHandleEnvelope({
        'type': 'call',
        'action': 'invite',
        'from': 42,
        'mode': 'audio',
        'peer_name': 'New Caller',
      });

      // Before the fix, this would still be stuck at ringingIncoming for
      // the OLD (id=99) call, or the new invite would have been silently
      // auto-rejected. After the fix, the stale state is cleared and the
      // new call rings through normally.
      expect(callService.callState, CallState.ringingIncoming);
      expect(callService.peer?.userId, 42);
      expect(callService.mode, CallMode.audio);
    },
  );

  test(
    'a genuinely recent (non-stale) busy state still rejects a new incoming call',
    () {
      // The staleness recovery must not turn into "always let calls
      // through" - a call that started moments ago and hasn't had time to
      // reach `active` yet is still legitimately busy.
      final callService = CallService();

      callService.debugHandleEnvelope({
        'type': 'call',
        'action': 'invite',
        'from': 99,
        'mode': 'video',
        'peer_name': 'Recent Caller',
      });
      expect(callService.callState, CallState.ringingIncoming);
      expect(callService.peer?.userId, 99);

      // No backdating this time - this state is fresh.
      callService.debugHandleEnvelope({
        'type': 'call',
        'action': 'invite',
        'from': 42,
        'mode': 'audio',
        'peer_name': 'New Caller',
      });

      // Still ringing for the original (id=99) caller - the new invite was
      // correctly rejected as busy, not let through.
      expect(callService.callState, CallState.ringingIncoming);
      expect(callService.peer?.userId, 99);
    },
  );

  test(
    'a live-pushed message envelope appends it and bumps the unread count',
    () {
      // Reproduces the messaging restructure: CallService._handleMessageEnvelope
      // is now purely a live-push convenience on top of persisted history
      // (routers/messages.py), but it still has to append the message and
      // track it as unread for the People Directory badge.
      final callService = CallService();
      expect(callService.unreadCountFor(7), 0);

      callService.debugHandleEnvelope({
        'type': 'message',
        'from': 7,
        'to': 1,
        'id': 42,
        'text': 'are you free for a consult?',
        'created_at': '2026-01-01T10:00:00Z',
      });

      final messages = callService.messagesWith(7);
      expect(messages, hasLength(1));
      expect(messages.first.id, 42);
      expect(messages.first.isMine, isFalse);
      expect(messages.first.text, 'are you free for a consult?');
      expect(callService.unreadCountFor(7), 1);
      expect(callService.totalUnreadCount, 1);

      // A second message from the same peer accumulates, it doesn't reset.
      callService.debugHandleEnvelope({
        'type': 'message',
        'from': 7,
        'to': 1,
        'text': 'nevermind, found someone else',
      });
      expect(callService.unreadCountFor(7), 2);
    },
  );

  test(
    'ChatMessage.fromJson resolves isMine/peerId from sender vs. recipient',
    () {
      // routers/messages.py's MessageResponse always carries both
      // sender_id/recipient_id (unlike the old live-envelope shape, which
      // only ever had "from") - fromJson has to work out which side of
      // that pair is "me" vs. "the peer" for both directions of a
      // conversation.
      final incoming = ChatMessage.fromJson({
        'id': 1,
        'sender_id': 7,
        'recipient_id': 1,
        'text': 'hi',
        'created_at': '2026-01-01T10:00:00Z',
      }, myUserId: 1);
      expect(incoming.isMine, isFalse);
      expect(incoming.peerId, 7);

      final outgoing = ChatMessage.fromJson({
        'id': 2,
        'sender_id': 1,
        'recipient_id': 7,
        'text': 'hey back',
        'created_at': '2026-01-01T10:01:00Z',
      }, myUserId: 1);
      expect(outgoing.isMine, isTrue);
      expect(outgoing.peerId, 7);
    },
  );

  test(
    'ConversationSummary.fromJson parses the conversations-list response shape',
    () {
      final summary = ConversationSummary.fromJson({
        'peer_id': 7,
        'peer_name': 'Nurse Priya',
        'last_text': 'see you at 3',
        'last_at': '2026-01-01T10:00:00Z',
        'unread_count': 3,
      });
      expect(summary.peerId, 7);
      expect(summary.peerName, 'Nurse Priya');
      expect(summary.unreadCount, 3);
    },
  );

  test(
    'CallLogEntry.fromJson parses the call-log response shape',
    () {
      final entry = CallLogEntry.fromJson({
        'id': 1,
        'peer_id': 6,
        'peer_name': 'superadmin',
        'direction': 'incoming',
        'mode': 'audio',
        'status': 'missed',
        'created_at': '2026-09-19T10:00:00Z',
        'ended_at': null,
      });
      expect(entry.peerId, 6);
      expect(entry.peerName, 'superadmin');
      expect(entry.isIncoming, isTrue);
      expect(entry.mode, CallMode.audio);
      expect(entry.status, 'missed');
    },
  );

  test(
    'CallPeer/ChatMessage models hold the fields the chat feature depends on',
    () {
      // Cheap sanity check that the models added for messaging still expose
      // exactly what call_service.dart and chat_screen.dart read from them.
      const peer = CallPeer(userId: 3, name: 'Nurse Priya');
      expect(peer.userId, 3);
      expect(peer.name, 'Nurse Priya');

      final msg = ChatMessage(
        peerId: 3,
        text: 'hello',
        isMine: true,
        timestamp: DateTime(2026, 1, 1),
      );
      expect(msg.peerId, 3);
      expect(msg.isMine, isTrue);
    },
  );
}
