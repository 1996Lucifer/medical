import 'dart:io';

void main() {
  var file = File('flutter_source/lib/camera/camera_screen.dart');
  var content = file.readAsStringSync();

  // Remove stream variables
  content = content.replaceAll(RegExp(r'  // Camera\n  bool _isConnected = false;\n  bool _isConnecting = false;\n  Uint8List\? _frameBytes;\n  WebSocketChannel\? _channel;\n  StreamSubscription\? _sub;\n  String\? _errorMessage;\n\n'), '');

  // Add import for camera_stream_view
  content = content.replaceFirst("import '../network/network_manager.dart';", "import '../network/network_manager.dart';\nimport 'camera_stream_view.dart';\nimport 'camera_status_service.dart';");

  // Fix initState
  content = content.replaceFirst("    _fetchCameraStatuses();\n    _statusTimer = Timer.periodic(const Duration(seconds: 15), (_) => _fetchCameraStatuses());", "");

  // Remove _statusTimer and _cameraStatuses declaration
  content = content.replaceAll(RegExp(r'  Map<int, bool> _cameraStatuses = \{\};\n  Timer\? _statusTimer;\n'), '');

  // Remove _fetchCameraStatuses method
  content = content.replaceAll(RegExp(r'  Future<void> _fetchCameraStatuses\(\) async \{[\s\S]*?\} catch \(\_\) \{\}\n  \}\n'), '');

  // Remove from dispose
  content = content.replaceFirst("    _statusTimer?.cancel();\n", "");
  content = content.replaceFirst("    _sub?.cancel();\n    _channel?.sink.close();\n", "");

  // Remove _connectStream and _disconnect methods
  content = content.replaceAll(RegExp(r'  // ── Stream ──[\s\S]*?// ── Attendance ──'), '// ── Attendance ──');

  // Fix _fetchCameras where it calls _connectStream
  content = content.replaceAll(RegExp(r'            // Delay connection slightly to allow build to finish\n            WidgetsBinding.instance.addPostFrameCallback\(\(\_\) \{\n              if \(mounted\) _connectStream\(\);\n            \}\);\n'), '');

  // Update ChoiceChip Selection logic
  content = content.replaceFirst(
'''                  onSelected: (selected) async {
                    if (selected) {
                      if (_isConnected || _isConnecting) {
                        await _disconnect();
                      }
                      setState(() => _selectedCamera = camera);
                      _connectStream();
                    }
                  },''',
'''                  onSelected: (selected) async {
                    if (selected) {
                      setState(() => _selectedCamera = camera);
                    }
                  },'''
  );

  // Update appbar Disconnect button
  content = content.replaceFirst(
'''        actions: [
          if (_isConnected)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton.icon(
                onPressed: _disconnect,
                icon: const Icon(Icons.stop_circle, color: Color(0xFFF43F5E), size: 20),
                label: const Text('Disconnect', style: TextStyle(color: Color(0xFFF43F5E), fontWeight: FontWeight.bold)),
              ),
            ),
        ],''',
'''        actions: [
          if (_selectedCamera != null)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton.icon(
                onPressed: () {
                  setState(() => _selectedCamera = null);
                },
                icon: const Icon(Icons.stop_circle, color: Color(0xFFF43F5E), size: 20),
                label: const Text('Disconnect', style: TextStyle(color: Color(0xFFF43F5E), fontWeight: FontWeight.bold)),
              ),
            ),
        ],'''
  );

  // Replace _buildVideoArea usage with CameraStreamView
  content = content.replaceAll(
'''                  clipBehavior: Clip.hardEdge,
                  child: _buildVideoArea(),''',
'''                  clipBehavior: Clip.hardEdge,
                  child: _selectedCamera != null 
                    ? CameraStreamView(cameraId: _selectedCamera!['id']) 
                    : const Center(child: Text('No camera selected', style: TextStyle(color: Colors.white54))),'''
  );

  // Remove _buildVideoArea definition
  content = content.replaceAll(RegExp(r'  Widget _buildVideoArea\(\) \{[\s\S]*?\}\n\n'), '');

  // ChoiceChip color logic replacement
  // We need to use ValueListenableBuilder around the Wrap.
  
  file.writeAsStringSync(content);
}
