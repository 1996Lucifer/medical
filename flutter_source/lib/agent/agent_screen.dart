import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../main.dart' show GlassCard, GlassBackground;
import '../providers/agent_provider.dart';
import '../providers/site_config_provider.dart';

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

class _AgentScreenState extends State<AgentScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToBottom = false;

  // Aetheris colors
  static const Color _primary = Color(0xFFffffff);
  static const Color _onSurface = Color(0xFFd6e3ff);
  static const Color _onSurfaceVariant = Color(0xFFbacac3);
  static const Color _primaryFixedDim = Color(0xFF38debb);

  static const Color _onPrimaryContainer = Color(0xFF00725e);
  static const Color _surfaceContainerHighest = Color(0xFF27354c);
  static const Color _surfaceContainerLowest = Color(0xFF010e24);

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<AgentProvider>(context, listen: false);
      provider.fetchSessions();
      provider.fetchHistory();
    });
    _scrollController.addListener(_scrollListener);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
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
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _pickFile(AgentProvider provider) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
        withData: true,
      );

      if (result != null) {
        provider.setAttachedFile(result.files.first);
      }
    } catch (e) {
      provider.addError("Error picking file: $e");
    }
  }

  Widget _buildSessionSidebar(AgentProvider provider) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text("CHAT HISTORY",
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: _onSurfaceVariant)),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: provider.sessions.length,
              itemBuilder: (context, index) {
                final session = provider.sessions[index];
                final isSelected = session['id'] == provider.currentSessionId;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.chat_bubble_outline,
                        size: 18,
                        color:
                            isSelected ? _primaryFixedDim : _onSurfaceVariant),
                    title: Text(
                      "Chat ${session['id']}",
                      style: TextStyle(
                        fontSize: 13,
                        color: isSelected ? _primary : _onSurfaceVariant,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    selected: isSelected,
                    selectedTileColor: _primaryFixedDim.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                            color: isSelected
                                ? _primaryFixedDim.withValues(alpha: 0.3)
                                : Colors.transparent)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 16, color: Colors.redAccent),
                      onPressed: () => provider.deleteSession(session['id']),
                      splashRadius: 20,
                      tooltip: "Delete Chat",
                    ),
                    onTap: () {
                      if (!isSelected) {
                        provider.loadSession(session['id']);
                        _scrollToBottomDelayed();
                      }
                    },
                  ),
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
    final provider = context.watch<AgentProvider>();
    final isMobile = MediaQuery.of(context).size.width < 900;

    Widget mainChatArea = Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(
                    isMobile ? 16 : 40, 0, isMobile ? 16 : 40, 16),
                itemCount:
                    provider.messages.length + (provider.isLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == provider.messages.length && provider.isLoading) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24, left: 16),
                      child: Consumer<SiteConfigProvider>(
                        builder: (context, config, _) {
                          return Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.3)),
                                ),
                                child: config.fullLogoUrl != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: Image.network(
                                          config.fullLogoUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(Icons.smart_toy,
                                                  color: _primaryFixedDim,
                                                  size: 20),
                                        ),
                                      )
                                    : const Icon(Icons.smart_toy,
                                        color: _primaryFixedDim, size: 20),
                              ),
                              const SizedBox(width: 16),
                              Text("${config.agentName} is processing...",
                                  style: const TextStyle(
                                      color: _onSurfaceVariant,
                                      fontStyle: FontStyle.italic)),
                            ],
                          );
                        },
                      ),
                    );
                  }
                  return _MessageBubble(msg: provider.messages[index]);
                },
              ),
              if (_showScrollToBottom)
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: FloatingActionButton.small(
                    onPressed: _scrollToBottom,
                    backgroundColor: _surfaceContainerHighest,
                    child: const Icon(Icons.arrow_downward, color: _primary),
                  ),
                ),
              if (_scrollController.hasClients &&
                  _scrollController.offset > 200)
                Positioned(
                  top: 16,
                  right: 16,
                  child: FloatingActionButton.small(
                    onPressed: _scrollToTop,
                    backgroundColor: _surfaceContainerHighest,
                    child: const Icon(Icons.arrow_upward, color: _primary),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
              isMobile ? 16 : 40, 0, isMobile ? 16 : 40, isMobile ? 16 : 40),
          child: _buildInputArea(provider),
        ),
      ],
    );

    Widget rightPanel = GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          _buildSessionSidebar(provider),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
          _buildSuggestionChips(provider),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
          _buildNewChatButton(provider),
        ],
      ),
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Consumer<SiteConfigProvider>(
          builder: (context, siteConfig, _) {
            return Row(
              children: [
                Text(
                  '${siteConfig.agentName} Command',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FadeTransition(
                        opacity: _pulseController,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              color: _primaryFixedDim,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                    color: _primaryFixedDim, blurRadius: 4)
                              ]),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('CLINICAL AGENT ACTIVE',
                          style: TextStyle(
                              color: _primaryFixedDim,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1)),
                    ],
                  ),
                )
              ],
            );
          },
        ),
        backgroundColor: Colors.black.withValues(alpha: 0.3),
        elevation: 0,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(color: Colors.transparent),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
              color: Colors.white.withValues(alpha: 0.05), height: 1.0),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: GlassBackground(
        child: SizedBox.expand(
          child: isMobile
              ? Padding(
                  padding:
                      const EdgeInsets.only(top: 16.0), // Account for appbar
                  child: Column(
                    children: [
                      Expanded(child: mainChatArea),
                    ],
                  ),
                )
              : Row(
                  children: [
                    Expanded(
                      flex: 7,
                      child: Padding(
                        padding: const EdgeInsets.only(
                            top: 16.0), // Account for appbar
                        child: mainChatArea,
                      ),
                    ),
                    Container(
                        width: 1, color: Colors.white.withValues(alpha: 0.1)),
                    SizedBox(width: 320, child: rightPanel),
                  ],
                ),
        ),
      ),
      endDrawer: isMobile
          ? Drawer(backgroundColor: _surfaceContainerLowest, child: rightPanel)
          : null,
    );
  }

  Widget _buildNewChatButton(AgentProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () {
            provider.startNewChat();
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text("New Chat",
              style: TextStyle(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _surfaceContainerHighest,
            foregroundColor: _primary,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionChips(AgentProvider provider) {
    final defaultSuggestions = [
      "Get Test 1's latest report",
      "List all active security rules",
      "Tell me updates about all the cameras",
      "Where is equipment?",
      "Show me the patient by MRN 12345"
    ];

    List<String> combined = List.from(provider.dynamicChips);
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
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Text("QUICK ACTIONS",
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: _onSurfaceVariant)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: combined.map((text) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: InkWell(
                    onTap: () {
                      _controller.text = text;
                      final txt = _controller.text;
                      _controller.clear();
                      provider.sendMessage(txt,
                          onScroll: _scrollToBottomDelayed);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _surfaceContainerLowest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.auto_awesome,
                              size: 16, color: _primaryFixedDim),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(text,
                                style: const TextStyle(
                                    fontSize: 13, color: _onSurface),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
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

  Widget _buildInputArea(AgentProvider provider) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: _surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))
          ]),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (provider.attachedFile != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0, left: 8.0, top: 8.0),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: _primaryFixedDim.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: ['png', 'jpg', 'jpeg'].contains(provider
                                  .attachedFile!.extension
                                  ?.toLowerCase()) &&
                              provider.attachedFile!.bytes != null
                          ? Image.memory(
                              provider.attachedFile!.bytes!,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 80,
                              height: 80,
                              color: _surfaceContainerLowest,
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
                        provider.setAttachedFile(null);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Icons.add_circle_outline,
                    color: _onSurfaceVariant, size: 28),
                onPressed: () => _pickFile(provider),
                tooltip: "Attach Document or Image",
              ),
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(color: _primary, fontSize: 16),
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText:
                        "Inquire about clinical data, protocols, or patient status...",
                    hintStyle: TextStyle(
                        color: _onSurfaceVariant.withValues(alpha: 0.5)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  onSubmitted: (_) {
                    final txt = _controller.text;
                    if (txt.trim().isEmpty && provider.attachedFile == null) {
                      return;
                    }
                    _controller.clear();
                    provider.sendMessage(txt, onScroll: _scrollToBottomDelayed);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4.0, right: 4.0),
                child: ElevatedButton(
                  onPressed: () {
                    final txt = _controller.text;
                    if (txt.trim().isEmpty && provider.attachedFile == null) {
                      return;
                    }
                    _controller.clear();
                    provider.sendMessage(txt, onScroll: _scrollToBottomDelayed);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryFixedDim,
                    foregroundColor: _onPrimaryContainer,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Send',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      SizedBox(width: 8),
                      Icon(Icons.send, size: 18),
                    ],
                  ),
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
  const _MessageBubble({required this.msg});

  // Aetheris colors inside bubble
  static const Color _primary = Color(0xFFffffff);
  static const Color _onSurface = Color(0xFFd6e3ff);
  static const Color _onSurfaceVariant = Color(0xFFbacac3);
  static const Color _primaryFixedDim = Color(0xFF38debb);
  static const Color _primaryContainer = Color(0xFF5ffbd6);
  static const Color _onPrimaryContainer = Color(0xFF00725e);
  static const Color _surfaceContainerHighest = Color(0xFF27354c);

  @override
  Widget build(BuildContext context) {
    final siteConfig = Provider.of<SiteConfigProvider>(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        mainAxisAlignment:
            msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!msg.isUser) ...[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: siteConfig.fullLogoUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        siteConfig.fullLogoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.smart_toy,
                            color: _primaryFixedDim,
                            size: 20),
                      ),
                    )
                  : const Icon(Icons.smart_toy,
                      color: _primaryFixedDim, size: 20),
            ),
            const SizedBox(width: 16),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: msg.isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: msg.isUser
                        ? _primaryContainer
                        : _surfaceContainerHighest.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(24).copyWith(
                      topLeft: msg.isUser
                          ? const Radius.circular(24)
                          : const Radius.circular(0),
                      topRight: msg.isUser
                          ? const Radius.circular(0)
                          : const Radius.circular(24),
                    ),
                    border: msg.isUser
                        ? null
                        : Border.all(
                            color: Colors.white.withValues(alpha: 0.1)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (msg.attachedImageBytes != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              msg.attachedImageBytes!,
                              width: 300,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      if (msg.text.isNotEmpty)
                        MarkdownBody(
                          data: msg.text,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(
                              color:
                                  msg.isUser ? _onPrimaryContainer : _onSurface,
                              fontSize: 16,
                              height: 1.5,
                            ),
                            tableBody: TextStyle(
                                fontSize: 14,
                                color: msg.isUser
                                    ? _onPrimaryContainer
                                    : _onSurface),
                            tableHead: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color:
                                  msg.isUser ? _onPrimaryContainer : _primary,
                            ),
                            tableBorder: TableBorder.all(
                              color: msg.isUser
                                  ? _onPrimaryContainer.withValues(alpha: 0.2)
                                  : _onSurfaceVariant.withValues(alpha: 0.2),
                              width: 1,
                            ),
                            tableCellsPadding: const EdgeInsets.all(12),
                            codeblockDecoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            code: TextStyle(
                                color: msg.isUser
                                    ? _onPrimaryContainer
                                    : _primaryFixedDim,
                                backgroundColor: Colors.transparent),
                          ),
                        ),
                    ],
                  ),
                ),
                if (msg.intent != null || msg.engine != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.info_outline,
                          size: 12, color: _onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        "Routed via: ${msg.intent} (${msg.engine})",
                        style: const TextStyle(
                            fontSize: 10,
                            color: _onSurfaceVariant,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ]
              ],
            ),
          ),
          if (msg.isUser) ...[
            const SizedBox(width: 16),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _primaryFixedDim,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.person,
                  color: _onPrimaryContainer, size: 20),
            ),
          ],
        ],
      ),
    );
  }
}
