import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'call_service.dart';

/// Text chat with one peer, backed by persisted history
/// (GET/POST /api/messages/*, see CallService.loadHistory/sendMessage) with
/// live updates pushed over the same signaling WebSocket the calling
/// feature already keeps open while both sides are connected. Not
/// end-to-end encrypted like kram's chat - this proves the messaging path
/// works end-to-end first; encryption is a follow-up, not a blocker for
/// that.
class ChatScreen extends StatefulWidget {
  final int peerId;
  final String peerName;

  const ChatScreen({super.key, required this.peerId, required this.peerName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _loadingHistory = true;

  @override
  void initState() {
    super.initState();
    final call = context.read<CallService>();
    // Not called synchronously here - markRead's first line is a
    // synchronous _unreadCountByPeer.remove()+notifyListeners(), and
    // calling that during initState() throws "setState() or
    // markNeedsBuild() called during build" whenever this screen is
    // mounted from a context that's itself still mid-build (e.g. pushed
    // from inbox_screen.dart while its own build hasn't finished). build()
    // below already schedules the equivalent post-frame call whenever
    // unreadCountFor(peerId) > 0, which covers this same "just opened a
    // conversation with unread messages" case safely.
    call.loadHistory(widget.peerId).whenComplete(() {
      if (!mounted) return;
      setState(() => _loadingHistory = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    });
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    context.read<CallService>().sendMessage(widget.peerId, text);
    _controller.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallService>();
    final messages = call.messagesWith(widget.peerId);
    final scheme = Theme.of(context).colorScheme;

    // A live push (_handleMessageEnvelope) while this chat is already open
    // still bumps the unread counter - clear it again rather than only on
    // initState, so the People Directory badge doesn't show a stale unread
    // count for a conversation the user is actively looking at. markRead
    // clears the local count synchronously, so this doesn't loop: the next
    // build sees unreadCountFor == 0 and skips the call.
    if (call.unreadCountFor(widget.peerId) > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) call.markRead(widget.peerId);
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.peerName)),
      body: Column(
        children: [
          Expanded(
            child: _loadingHistory
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                ? const Center(child: Text('No messages yet'))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, i) {
                      final m = messages[i];
                      return Align(
                        alignment:
                            m.isMine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          decoration: BoxDecoration(
                            color: m.isMine
                                ? scheme.primary
                                : scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            m.text,
                            style: TextStyle(
                              color: m.isMine ? scheme.onPrimary : scheme.onSurface,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Message...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
