import re

with open('flutter_source/lib/camera/camera_stream_view.dart', 'r') as f:
    content = f.read()

# Add Timer _reconnectTimer
content = content.replace("  String? _errorMessage;", "  String? _errorMessage;\n  Timer? _reconnectTimer;")

# Add _scheduleReconnect method
reconnect_method = """
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (!mounted) return;
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        _disconnect();
        _connectStream();
      }
    });
  }
"""

content = content.replace("  Future<void> _disconnect() async {", reconnect_method + "\n  Future<void> _disconnect() async {")

# Update onError
content = content.replace(
"""        onError: (e) {
          if (mounted) {
            setState(() {
              _errorMessage = 'Error: $e';
              _isConnected = false;
              _isConnecting = false;
            });
          }
        },""",
"""        onError: (e) {
          if (mounted) {
            setState(() {
              _errorMessage = 'Error: $e';
              _isConnected = false;
              _isConnecting = false;
            });
            _scheduleReconnect();
          }
        },"""
)

# Update onDone
content = content.replace(
"""        onDone: () {
          if (mounted) {
            setState(() {
              _isConnected = false;
              _isConnecting = false;
            });
          }
        },""",
"""        onDone: () {
          if (mounted) {
            setState(() {
              _isConnected = false;
              _isConnecting = false;
            });
            _scheduleReconnect();
          }
        },"""
)

# Also for the initial try/catch inside _connectStream
content = content.replace(
"""    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _errorMessage = 'Could not connect: $e';
        });
      }
    }""",
"""    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _errorMessage = 'Could not connect: $e';
        });
        _scheduleReconnect();
      }
    }"""
)

# Update _disconnect to cancel timer
content = content.replace(
"""  Future<void> _disconnect() async {
    await _sub?.cancel();""",
"""  Future<void> _disconnect() async {
    _reconnectTimer?.cancel();
    await _sub?.cancel();"""
)

with open('flutter_source/lib/camera/camera_stream_view.dart', 'w') as f:
    f.write(content)
