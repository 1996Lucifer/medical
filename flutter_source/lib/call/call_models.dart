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

/// A single persisted chat message (backend/models.py's StaffMessage,
/// served by routers/messages.py). `id` is null only for a message this
/// device just sent optimistically, before the POST response comes back
/// with the real server-assigned id.
class ChatMessage {
  final int? id;
  final int peerId;
  final String text;
  final bool isMine;
  final DateTime timestamp;

  ChatMessage({
    this.id,
    required this.peerId,
    required this.text,
    required this.isMine,
    required this.timestamp,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json, {required int myUserId}) {
    final senderId = json['sender_id'] as int;
    final recipientId = json['recipient_id'] as int;
    return ChatMessage(
      id: json['id'] as int?,
      peerId: senderId == myUserId ? recipientId : senderId,
      text: json['text'] as String,
      isMine: senderId == myUserId,
      timestamp: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// One row of `GET /api/messages/conversations` - who a staff member has
/// exchanged messages with, most recent first, with an unread count for
/// the People Directory's per-contact badge.
class ConversationSummary {
  final int peerId;
  final String peerName;
  final String lastText;
  final DateTime lastAt;
  final int unreadCount;

  ConversationSummary({
    required this.peerId,
    required this.peerName,
    required this.lastText,
    required this.lastAt,
    required this.unreadCount,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    return ConversationSummary(
      peerId: json['peer_id'] as int,
      peerName: json['peer_name'] as String,
      lastText: json['last_text'] as String,
      lastAt: DateTime.parse(json['last_at'] as String),
      unreadCount: json['unread_count'] as int,
    );
  }
}

/// One row of `GET /api/calls/log` - a past call attempt, whether or not
/// the other side is someone who shows up in the People Directory (e.g. an
/// admin/superadmin login with no Staff row). This is how a recipient
/// finds out "who called me" after the fact, since the signaling relay
/// itself (routers/calls.py's /ws/calls) keeps no history of its own.
class CallLogEntry {
  final int id;
  final int peerId;
  final String peerName;
  final bool isIncoming;
  final CallMode mode;
  final String status; // ringing/answered/declined/missed/unavailable
  final DateTime createdAt;

  CallLogEntry({
    required this.id,
    required this.peerId,
    required this.peerName,
    required this.isIncoming,
    required this.mode,
    required this.status,
    required this.createdAt,
  });

  factory CallLogEntry.fromJson(Map<String, dynamic> json) {
    return CallLogEntry(
      id: json['id'] as int,
      peerId: json['peer_id'] as int,
      peerName: json['peer_name'] as String,
      isIncoming: json['direction'] == 'incoming',
      mode: json['mode'] == 'video' ? CallMode.video : CallMode.audio,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
