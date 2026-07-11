import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;

import '../main.dart';
import '../network/api_routes.dart';
import '../network/network_manager.dart';

class AgentMessage {
  final String text;
  final bool isUser;
  final String? intent;
  final String? engine;
  final Uint8List? attachedImageBytes;

  AgentMessage({
    required this.text,
    required this.isUser,
    this.intent,
    this.engine,
    this.attachedImageBytes,
  });
}

class AgentScreen extends StatefulWidget {
  const AgentScreen({super.key});

  @override
  State<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends State<AgentScreen> {
  final TextEditingController _controller = TextEditingController();
  List<AgentMessage> _messages = [
    AgentMessage(
      text:
          "Hello! I am Aura, your AI Medical Assistant. How can I help you today?",
      isUser: false,
    )
  ];
  List<String> _dynamicChips = [];
  bool _isLoading = false;
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToBottom = false;
  PlatformFile? _attachedFile;

  String _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
  List<Map<String, dynamic>> _sessions = [];

  @override
  void initState() {
    super.initState();
    _fetchSessions();
    _fetchHistory();
    _scrollController.addListener(_scrollListener);
  }

  Future<void> _fetchSessions() async {
    try {
      final response = await http.get(Uri.parse(ApiRoutes.agentSessions));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _sessions = List<Map<String, dynamic>>.from(data['sessions'] ?? []);
        });
      }
    } catch (e) {
      debugPrint("Error fetching sessions: $e");
    }
  }

  Future<void> _loadSession(String sessionId) async {
    setState(() {
      _currentSessionId = sessionId;
      _isLoading = true;
      _messages = [];
    });

    try {
      final response =
          await http.get(Uri.parse(ApiRoutes.agentSession(sessionId)));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final history = data['messages'] ?? [];

        setState(() {
          _messages = history.map<AgentMessage>((msg) {
            return AgentMessage(
              text: msg['content'],
              isUser: msg['role'] == 'user',
            );
          }).toList();
        });
        _scrollToBottomDelayed();
      }
    } catch (e) {
      _addError("Error loading session: $e");
    } finally {
      setState(() => _isLoading = false);
      _fetchHistory();
    }
  }

  Future<void> _deleteSession(String sessionId) async {
    try {
      final response = await http.delete(Uri.parse(ApiRoutes.agentSession(sessionId)));
      if (response.statusCode == 200) {
        if (_currentSessionId == sessionId) {
          _startNewChat();
        } else {
          _fetchSessions();
        }
      }
    } catch (e) {
      debugPrint("Error deleting session: $e");
    }
  }

  void _startNewChat() {
    setState(() {
      _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
      _messages = [
        AgentMessage(
          text:
              "Hello! I am Aura, your AI Medical Assistant. How can I help you today?",
          isUser: false,
        )
      ];
    });
    _fetchHistory();
  }

  void _scrollListener() {
    if (_scrollController.hasClients) {
      if (_scrollController.offset <
          _scrollController.position.maxScrollExtent - 50) {
        if (!_showScrollToBottom) setState(() => _showScrollToBottom = true);
      } else {
        if (_showScrollToBottom) setState(() => _showScrollToBottom = false);
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _scrollToBottomDelayed() {
    Future.delayed(const Duration(milliseconds: 100), () {
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchHistory() async {
    try {
      final response = await http.get(
          Uri.parse("${ApiRoutes.agentHistory}?session_id=$_currentSessionId"));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _dynamicChips = List<String>.from(data['queries'] ?? []);
        });
      }
    } catch (e) {
      // Ignore if server is down, we just won't show chips
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _attachedFile == null) return;

    setState(() {
      String displayMsg = text;
      bool isImage = false;
      Uint8List? imageBytes;

      if (_attachedFile != null) {
        final ext = _attachedFile!.extension?.toLowerCase();
        isImage = ['png', 'jpg', 'jpeg'].contains(ext);
        if (isImage && _attachedFile!.bytes != null) {
          imageBytes = _attachedFile!.bytes;
        } else {
          displayMsg += "\n\n[Attached File: ${_attachedFile!.name}]";
        }
      }

      _messages.add(AgentMessage(
        text: displayMsg.trim(),
        isUser: true,
        attachedImageBytes: imageBytes,
      ));
      _isLoading = true;
    });

    final currentText =
        text.isEmpty ? "Please analyze this attached file." : text;
    final currentFile = _attachedFile;

    _controller.clear();
    setState(() {
      _attachedFile = null;
    });
    _scrollToBottomDelayed();

    try {
      final request =
          NetworkManager.instance.multipartRequest('POST', ApiRoutes.agentChat);
      request.fields['message'] = currentText;
      request.fields['session_id'] = _currentSessionId;

      if (currentFile != null) {
        request.files.add(http.MultipartFile.fromBytes(
            'file', currentFile.bytes!,
            filename: currentFile.name));
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _messages.add(AgentMessage(
            text: data['response'] ?? "No response",
            isUser: false,
            intent: data['intent'],
            engine: data['engine'],
          ));
        });
        _scrollToBottomDelayed();
        // Refresh history and sessions after a successful message
        _fetchHistory();
        _fetchSessions();
      } else {
        _addError("Error connecting to Agent. Code: ${response.statusCode}");
      }
    } catch (e) {
      _addError("Network error: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
        withData: true,
      );

      if (result != null) {
        setState(() {
          _attachedFile = result.files.first;
        });
      }
    } catch (e) {
      _addError("Error picking file: $e");
    }
  }

  Future<void> _showUsageMetrics() async {
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) {
          return FutureBuilder(
            future: http.get(Uri.parse(ApiRoutes.agentUsage)),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                    height: 300,
                    child: Center(child: CircularProgressIndicator()));
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return const SizedBox(
                    height: 300,
                    child: Center(child: Text("Error loading metrics.")));
              }

              final data = jsonDecode(snapshot.data!.body);
              final List usage = data['usage'] ?? [];

              return Container(
                padding: const EdgeInsets.all(16),
                height: 400,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Agent Usage & Performance",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.builder(
                        itemCount: usage.length,
                        itemBuilder: (context, index) {
                          final item = usage[index];
                          final isCacheHit = item['strategy'] == 'CACHE';
                          return ListTile(
                            leading: Icon(
                                isCacheHit ? Icons.bolt : Icons.memory,
                                color: isCacheHit ? Colors.amber : Colors.teal),
                            title: Text(
                                "Intent: ${item['intent']} | Strategy: ${item['strategy']}"),
                            subtitle: Text(
                                "Latency: ${item['latency'].toStringAsFixed(2)}s | Model: ${item['model'] ?? 'N/A'}"),
                          );
                        },
                      ),
                    )
                  ],
                ),
              );
            },
          );
        });
  }

  void _addError(String text) {
    setState(() {
      _messages.add(AgentMessage(text: text, isUser: false));
    });
  }

  Widget _buildSessionSidebar() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text("Chat History",
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: _sessions.length,
              itemBuilder: (context, index) {
                final session = _sessions[index];
                final isSelected = session['id'] == _currentSessionId;
                final themeColor = Colors.teal;
                return ListTile(
                  dense: true,
                  leading: Icon(Icons.chat_bubble_outline,
                      size: 18, color: isSelected ? themeColor : Colors.grey),
                  title: Text(
                    "Chat ${session['id']}",
                    style: TextStyle(
                      fontSize: 13,
                      color: isSelected ? themeColor : Colors.black87,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  selected: isSelected,
                  selectedTileColor: themeColor.withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.grey),
                    onPressed: () => _deleteSession(session['id']),
                    splashRadius: 20,
                    tooltip: "Delete Chat",
                  ),
                  onTap: () {
                    if (!isSelected) {
                      _loadSession(session['id']);
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text("Aura AI",
              style: TextStyle(
                  color: Colors.black87, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white.withValues(alpha: 0.5),
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black87),
          actions: [
            IconButton(
              icon: const Icon(Icons.analytics_outlined),
              onPressed: _showUsageMetrics,
              tooltip: "View Usage Metrics",
            )
          ],
        ),
        body: Row(
          children: [
            Expanded(
              flex: 8,
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length + (_isLoading ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _messages.length && _isLoading) {
                              return const Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding:
                                      EdgeInsets.only(bottom: 12, left: 16),
                                  child: Text("Aura is typing...",
                                      style: TextStyle(
                                          color: Colors.grey,
                                          fontStyle: FontStyle.italic)),
                                ),
                              );
                            }
                            return _MessageBubble(msg: _messages[index]);
                          },
                        ),
                        if (_showScrollToBottom)
                          Positioned(
                            bottom: 16,
                            right: 16,
                            child: FloatingActionButton.small(
                              onPressed: _scrollToBottom,
                              backgroundColor: Colors.teal,
                              child: const Icon(Icons.arrow_downward,
                                  color: Colors.white),
                            ),
                          ),
                        if (_scrollController.hasClients &&
                            _scrollController.offset > 200)
                          Positioned(
                            top: 16,
                            right: 16,
                            child: FloatingActionButton.small(
                              onPressed: _scrollToTop,
                              backgroundColor:
                                  Theme.of(context).colorScheme.secondary,
                              child: const Icon(Icons.arrow_upward,
                                  color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 16.0, bottom: 16.0),
                    child: GlassCard(
                      padding: EdgeInsets.zero,
                      child: _buildInputArea(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Padding(
                padding:
                    const EdgeInsets.only(right: 16.0, top: 16.0, bottom: 16.0),
                child: GlassCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 16.0),
                      ),
                      _buildSessionSidebar(),
                      const Divider(height: 1, color: Colors.black12),
                      _buildSuggestionChips(),
                      const Divider(height: 1, color: Colors.black12),
                      _buildNewChatButton(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewChatButton() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () {
            _startNewChat();
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text("New Chat",
              style: TextStyle(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionChips() {
    final defaultSuggestions = [
      "Get Test 1's latest report",
      "List all active security rules",
      "Tell me updates about all the cameras",
      "Where is equipment?",
      "Show me the patient by MRN 12345"
    ];

    // Combine dynamic history with defaults, keeping unique up to 5
    List<String> combined = List.from(_dynamicChips);
    for (String defMsg in defaultSuggestions) {
      if (!combined.contains(defMsg)) {
        combined.add(defMsg);
      }
      if (combined.length >= 5) break;
    }

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text("Quick Options",
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              children: combined.map((text) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ActionChip(
                      label: Text(text,
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.secondary)),
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .secondary
                          .withValues(alpha: 0.1),
                      side: BorderSide(
                          color: Theme.of(context)
                              .colorScheme
                              .secondary
                              .withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      onPressed: () {
                        _controller.text = text;
                        _sendMessage();
                      },
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_attachedFile != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: ['png', 'jpg', 'jpeg'].contains(
                                  _attachedFile!.extension?.toLowerCase()) &&
                              _attachedFile!.bytes != null
                          ? Image.memory(
                              _attachedFile!.bytes!,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 80,
                              height: 80,
                              color: Colors.grey[200],
                              child: const Icon(Icons.picture_as_pdf,
                                  size: 40, color: Colors.redAccent),
                            ),
                    ),
                  ),
                  Positioned(
                    top: -8,
                    right: -8,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _attachedFile = null;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.attach_file, color: Colors.grey),
                onPressed: _pickFile,
                tooltip: "Attach Document or Image",
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: "Ask Aura anything...",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: const Color(0xFF009688),
                radius: 24,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: _sendMessage,
                ),
              )
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final AgentMessage msg;
  const _MessageBubble({Key? key, required this.msg}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: msg.isUser ? const Color(0xFF009688) : Colors.white,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: msg.isUser
                ? const Radius.circular(0)
                : const Radius.circular(16),
            bottomLeft: msg.isUser
                ? const Radius.circular(16)
                : const Radius.circular(0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!msg.isUser)
              const Padding(
                padding: EdgeInsets.only(bottom: 4.0),
                child: Text("Aura",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.teal,
                        fontSize: 12)),
              ),
            if (msg.attachedImageBytes != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    msg.attachedImageBytes!,
                    width: 250,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            if (msg.text.isNotEmpty)
              MarkdownBody(
                data: msg.text,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(
                    color: msg.isUser ? Colors.white : Colors.black87,
                    fontSize: 15,
                  ),
                  tableBody:
                      const TextStyle(fontSize: 14, color: Colors.black87),
                  tableHead: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  tableBorder: TableBorder.all(
                    color: Colors.grey.shade300,
                    width: 1,
                  ),
                  tableCellsPadding: const EdgeInsets.all(8),
                ),
              ),
            if (msg.intent != null || msg.engine != null) ...[
              const SizedBox(height: 8),
              Text(
                "Routed via: ${msg.intent} (${msg.engine})",
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
