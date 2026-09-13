enum CallMode { audio, video }

enum CallState {
  idle,
  ringingOutgoing,
  ringingIncoming,
  connecting,
  active,
  ended,
}

/// Who's on the other end of a call - just enough to render the incoming
/// call dialog and in-call header without a separate lookup.
class CallPeer {
  final int userId;
  final String name;

  const CallPeer({required this.userId, required this.name});
}
