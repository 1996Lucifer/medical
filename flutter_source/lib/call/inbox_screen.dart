import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'call_models.dart';
import 'call_service.dart';
import 'chat_screen.dart';

/// Everyone who has ever messaged or called this account, regardless of
/// whether they show up as a card in the People Directory. The Directory
/// only lists Staff-table rows (see people_directory_screen.dart), so an
/// admin/superadmin login - which has no Staff record by definition - is
/// invisible there. That meant a message or call from an admin/superadmin
/// simply had nowhere to surface for the recipient: the message was
/// persisted and the unread count was computed correctly, but the only
/// place either was ever displayed was a per-contact badge on a Directory
/// card that didn't exist for that sender. This screen is sourced
/// entirely from GET /api/messages/conversations and GET /api/calls/log,
/// neither of which depends on the Staff table, so it's how "who messaged
/// or called me" stays answerable no matter who the other side is
/// (/investigate 2026-09-19).
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<ConversationSummary> _conversations = [];
  List<CallLogEntry> _calls = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final call = context.read<CallService>();
    final results = await Future.wait([
      call.loadConversations(),
      call.loadCallLog(),
    ]);
    if (!mounted) return;
    setState(() {
      _conversations = results[0] as List<ConversationSummary>;
      _calls = results[1] as List<CallLogEntry>;
      _isLoading = false;
    });
  }

  void _callBack(int peerId, String peerName, CallMode mode) {
    context.read<CallService>().startCall(CallPeer(userId: peerId, name: peerName), mode);
  }

  void _openChat(int peerId, String peerName) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(peerId: peerId, peerName: peerName),
          ),
        )
        .then((_) => _load());
  }

  String _callStatusLabel(CallLogEntry entry) {
    switch (entry.status) {
      case 'answered':
        return entry.isIncoming ? 'Incoming call' : 'Outgoing call';
      case 'declined':
        return entry.isIncoming ? 'You declined' : 'Declined';
      case 'unavailable':
        return 'Not reachable';
      case 'missed':
      default:
        return entry.isIncoming ? 'Missed call' : 'No answer';
    }
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Messages${_conversations.isEmpty ? '' : ' (${_conversations.length})'}'),
            Tab(text: 'Calls${_calls.isEmpty ? '' : ' (${_calls.length})'}'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _conversations.isEmpty
                      ? const _EmptyState(label: 'No messages yet')
                      : ListView.separated(
                          itemCount: _conversations.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final c = _conversations[i];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: scheme.secondary.withValues(alpha: 0.2),
                                child: Text(
                                  c.peerName.isNotEmpty ? c.peerName[0].toUpperCase() : '?',
                                  style: TextStyle(color: scheme.secondary, fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(c.peerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(c.lastText, maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(_relativeTime(c.lastAt),
                                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                                  if (c.unreadCount > 0) ...[
                                    const SizedBox(height: 4),
                                    CircleAvatar(
                                      radius: 9,
                                      backgroundColor: scheme.error,
                                      child: Text('${c.unreadCount}',
                                          style: TextStyle(fontSize: 10, color: scheme.onError)),
                                    ),
                                  ],
                                ],
                              ),
                              onTap: () => _openChat(c.peerId, c.peerName),
                            );
                          },
                        ),
                  _calls.isEmpty
                      ? const _EmptyState(label: 'No calls yet')
                      : ListView.separated(
                          itemCount: _calls.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final entry = _calls[i];
                            final missed = entry.isIncoming &&
                                (entry.status == 'missed' || entry.status == 'unavailable');
                            return ListTile(
                              leading: Icon(
                                entry.isIncoming ? Icons.call_received : Icons.call_made,
                                color: missed ? scheme.error : scheme.secondary,
                              ),
                              title: Text(entry.peerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                '${_callStatusLabel(entry)} · ${entry.mode == CallMode.video ? 'Video' : 'Audio'} · ${_relativeTime(entry.createdAt)}',
                                style: missed ? TextStyle(color: scheme.error) : null,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.call, color: scheme.secondary, size: 20),
                                    tooltip: 'Call back',
                                    onPressed: () => _callBack(entry.peerId, entry.peerName, CallMode.audio),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.chat_bubble_outline, color: scheme.secondary, size: 20),
                                    tooltip: 'Message',
                                    onPressed: () => _openChat(entry.peerId, entry.peerName),
                                  ),
                                ],
                              ),
                              onTap: () => _openChat(entry.peerId, entry.peerName),
                            );
                          },
                        ),
                ],
              ),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String label;
  const _EmptyState({required this.label});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Center(
          child: Text(label,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}
