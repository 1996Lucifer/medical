import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../network/api_routes.dart';
import '../network/network_manager.dart';
import '../agent/agent_screen.dart'; // For AgentMessage

class AgentProvider extends ChangeNotifier {
  List<AgentMessage> _messages = [
    AgentMessage(
      text: "Hello! I am Aura, your AI Medical Assistant. How can I help you today?",
      isUser: false,
    )
  ];
  List<String> _dynamicChips = [];
  bool _isLoading = false;
  String _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
  List<Map<String, dynamic>> _sessions = [];
  PlatformFile? _attachedFile;

  List<AgentMessage> get messages => _messages;
  List<String> get dynamicChips => _dynamicChips;
  bool get isLoading => _isLoading;
  String get currentSessionId => _currentSessionId;
  List<Map<String, dynamic>> get sessions => _sessions;
  PlatformFile? get attachedFile => _attachedFile;

  void setAttachedFile(PlatformFile? file) {
    _attachedFile = file;
    notifyListeners();
  }

  Future<void> fetchSessions() async {
    try {
      final response = await http.get(Uri.parse(ApiRoutes.agentSessions));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _sessions = List<Map<String, dynamic>>.from(data['sessions'] ?? []);
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error fetching sessions: $e");
    }
  }

  Future<void> loadSession(String sessionId) async {
    _currentSessionId = sessionId;
    _isLoading = true;
    _messages = [];
    notifyListeners();

    try {
      final response = await http.get(Uri.parse(ApiRoutes.agentSession(sessionId)));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final history = data['messages'] ?? [];
        _messages = history.map<AgentMessage>((msg) {
          return AgentMessage(
            text: msg['content'],
            isUser: msg['role'] == 'user',
          );
        }).toList();
      }
    } catch (e) {
      addError("Error loading session: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
      fetchHistory();
    }
  }

  Future<void> deleteSession(String sessionId) async {
    try {
      final response = await http.delete(Uri.parse(ApiRoutes.agentSession(sessionId)));
      if (response.statusCode == 200) {
        if (_currentSessionId == sessionId) {
          startNewChat();
        } else {
          fetchSessions();
        }
      }
    } catch (e) {
      debugPrint("Error deleting session: $e");
    }
  }

  void startNewChat() {
    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _messages = [
      AgentMessage(
        text: "Hello! I am Aura, your AI Medical Assistant. How can I help you today?",
        isUser: false,
      )
    ];
    notifyListeners();
    fetchHistory();
  }

  Future<void> fetchHistory() async {
    try {
      final response = await http.get(Uri.parse("${ApiRoutes.agentHistory}?session_id=$_currentSessionId"));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _dynamicChips = List<String>.from(data['queries'] ?? []);
        notifyListeners();
      }
    } catch (e) {
      // Ignore if server is down, we just won't show chips
    }
  }

  Future<void> sendMessage(String text, {VoidCallback? onScroll}) async {
    if (text.isEmpty && _attachedFile == null) return;

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
    notifyListeners();

    final currentText = text.isEmpty ? "Please analyze this attached file." : text;
    final currentFile = _attachedFile;
    _attachedFile = null;
    if (onScroll != null) onScroll();
    notifyListeners();

    try {
      final request = NetworkManager.instance.multipartRequest('POST', ApiRoutes.agentChat);
      request.fields['message'] = currentText;
      request.fields['session_id'] = _currentSessionId;

      if (currentFile != null) {
        request.files.add(http.MultipartFile.fromBytes('file', currentFile.bytes!, filename: currentFile.name));
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _messages.add(AgentMessage(
          text: data['response'] ?? "No response",
          isUser: false,
          intent: data['intent'],
          engine: data['engine'],
        ));
        if (onScroll != null) onScroll();
        fetchHistory();
        fetchSessions();
      } else {
        addError("Error connecting to Agent. Code: ${response.statusCode}");
      }
    } catch (e) {
      addError("Network error: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void addError(String text) {
    _messages.add(AgentMessage(text: text, isUser: false));
    notifyListeners();
  }
}
