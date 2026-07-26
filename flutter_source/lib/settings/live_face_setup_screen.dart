import 'dart:async';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../network/api_routes.dart';

const Color _bgBase = Color(0xFF041329);
const Color _tealAccent = Color(0xFF5ffbd6);
const Color _surfaceContainer = Color(0xFF112036);
const Color _surfaceContainerHigh = Color(0xFF1c2a41);
const Color _textColor = Color(0xFFd6e3ff);
const Color _textVariant = Color(0xFFbacac3);
const Color _outlineVariant = Color(0xFF3c4a45);

class LiveFaceSetupScreen extends StatefulWidget {
  final int staffId;
  const LiveFaceSetupScreen({super.key, required this.staffId});

  @override
  State<LiveFaceSetupScreen> createState() => _LiveFaceSetupScreenState();
}

class _LiveFaceSetupScreenState extends State<LiveFaceSetupScreen> with SingleTickerProviderStateMixin {
  CameraController? _controller;
  WebSocketChannel? _channel;
  Timer? _timer;
  List<CameraDescription> _cameras = [];
  int _currentCameraIndex = 0;

  bool _isInitializing = true;
  String _currentInstruction = "Initializing System Handshake...";
  List<String> _completedAngles = [];
  bool _isComplete = false;

  late AnimationController _scanController;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
        if (_cameras.isEmpty) throw Exception('No cameras found');

        // Try to start with front camera if available
        _currentCameraIndex = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
        if (_currentCameraIndex == -1) _currentCameraIndex = 0;
      }

      final camera = _cameras[_currentCameraIndex];

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      if (!mounted) return;

      setState(() => _isInitializing = false);
      _connectWebSocket();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _currentInstruction = "Camera initialization failed: $e";
        });
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No other cameras found')));
      return;
    }

    setState(() => _isInitializing = true);

    _timer?.cancel();
    _channel?.sink.close();
    await _controller?.dispose();
    _controller = null;

    _currentCameraIndex = (_currentCameraIndex + 1) % _cameras.length;

    await _initCamera();
  }

  void _connectWebSocket() {
    final wsUrl = ApiRoutes.staffLiveSetupWs(widget.staffId);
    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

    _channel!.stream.listen((message) {
      if (!mounted) return;
      try {
        final data = jsonDecode(message);

        setState(() {
          _currentInstruction = data['instruction'] ?? '';
          _completedAngles = (data['completed'] as List<dynamic>).cast<String>();

          if (data['status'] == 'complete') {
            _isComplete = true;
            _timer?.cancel();
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                Navigator.pop(context, true); // true indicates success
              }
            });
          }
        });
      } catch (e) {
        debugPrint("Error parsing ws message: $e");
      }
    }, onError: (err) {
      if (mounted) {
        setState(() => _currentInstruction = "Connection Error: $err");
      }
    }, onDone: () {
      if (mounted && !_isComplete) {
        setState(() => _currentInstruction = "Connection Closed.");
      }
    });

    // Start streaming frames
    _timer = Timer.periodic(const Duration(milliseconds: 600), (t) async {
      if (_isComplete || _controller == null || !_controller!.value.isInitialized || _controller!.value.isTakingPicture) {
        return;
      }

      try {
        final xFile = await _controller!.takePicture();
        final bytes = await xFile.readAsBytes();
        _channel?.sink.add(bytes);
      } catch (e) {
        debugPrint("Error capturing frame: $e");
      }
    });
  }

  @override
  void dispose() {
    _scanController.dispose();
    _timer?.cancel();
    _channel?.sink.close();
    _controller?.dispose();
    super.dispose();
  }

  Widget _buildCheckmark(String angle, String label) {
    final isDone = _completedAngles.contains(angle);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDone ? _tealAccent.withValues(alpha: 0.1) : _surfaceContainerHigh,
        border: Border.all(color: isDone ? _tealAccent.withValues(alpha: 0.5) : _outlineVariant.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDone ? Icons.check_circle : Icons.circle_outlined,
            color: isDone ? _tealAccent : _textVariant,
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              color: isDone ? _tealAccent : _textVariant,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgBase,
      appBar: AppBar(
        title: const Text('Staff Biometric Registration', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
            onPressed: _switchCamera,
            tooltip: 'Switch Camera',
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator(color: _tealAccent))
          : LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 900) {
                  return Row(
                    children: [
                      Expanded(flex: 7, child: _buildCameraFeed()),
                      Expanded(flex: 5, child: _buildRegistrationPanel()),
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(flex: 6, child: _buildCameraFeed()),
                    Expanded(flex: 5, child: _buildRegistrationPanel()),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildCameraFeed() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: _tealAccent));
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Container(
        decoration: BoxDecoration(
          color: _surfaceContainer,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _tealAccent.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(color: _tealAccent.withValues(alpha: 0.05), blurRadius: 30, spreadRadius: 5),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: 1 / _controller!.value.aspectRatio,
                child: CameraPreview(_controller!),
              ),
            ),
            // Darken overlay
            Container(color: Colors.black.withValues(alpha: 0.3)),

            // Central Target Frame
            Center(
              child: Container(
                width: 280,
                height: 340,
                decoration: BoxDecoration(
                  border: Border.all(color: _tealAccent.withValues(alpha: 0.4), width: 1, style: BorderStyle.solid),
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Stack(
                  children: [
                    // Dashed inner border
                    Positioned.fill(
                      child: Container(
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          border: Border.all(color: _tealAccent.withValues(alpha: 0.2), width: 2),
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                    ),
                    // Scanning line animation
                    AnimatedBuilder(
                      animation: _scanController,
                      builder: (context, child) {
                        return Positioned(
                          top: _scanController.value * 320,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 2,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Colors.transparent, _tealAccent, Colors.transparent],
                              ),
                              boxShadow: [
                                BoxShadow(color: _tealAccent, blurRadius: 10, spreadRadius: 2)
                              ]
                            ),
                          ),
                        );
                      }
                    ),
                    // Match Text
                    Positioned(
                      top: -14,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: _tealAccent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'SUBJECT_DETECTED',
                            style: TextStyle(color: _bgBase, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, fontFamily: 'monospace'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Corners
            Positioned(top: 32, left: 32, child: _buildCorner(top: true, left: true)),
            Positioned(top: 32, right: 32, child: _buildCorner(top: true, left: false)),
            Positioned(bottom: 32, left: 32, child: _buildCorner(top: false, left: true)),
            Positioned(bottom: 32, right: 32, child: _buildCorner(top: false, left: false)),

            // Mock Monospace Stats
            Positioned(
              top: 24,
              right: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildMonoText('FPS: 60.0'),
                  _buildMonoText('ISO: 400'),
                  _buildMonoText('EXP: -0.5'),
                ],
              ),
            ),
            Positioned(
              bottom: 24,
              left: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMonoText('LAT: 40.7128 N'),
                  _buildMonoText('LONG: 74.0060 W'),
                  _buildMonoText('NODE: AEGIS_CAM_04'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCorner({required bool top, required bool left}) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        border: Border(
          top: top ? BorderSide(color: _tealAccent.withValues(alpha: 0.6), width: 2) : BorderSide.none,
          bottom: !top ? BorderSide(color: _tealAccent.withValues(alpha: 0.6), width: 2) : BorderSide.none,
          left: left ? BorderSide(color: _tealAccent.withValues(alpha: 0.6), width: 2) : BorderSide.none,
          right: !left ? BorderSide(color: _tealAccent.withValues(alpha: 0.6), width: 2) : BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildMonoText(String text) {
    return Text(
      text,
      style: TextStyle(color: _tealAccent.withValues(alpha: 0.8), fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold),
    );
  }

  Widget _buildRegistrationPanel() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 24, 24),
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: _surfaceContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _outlineVariant.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _tealAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.fingerprint, color: _tealAccent, size: 28),
                ),
                const SizedBox(width: 16),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Live AI Enrollment', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    Text('Follow the prompts to configure access.', style: TextStyle(color: _textVariant, fontSize: 14)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 48),
            const Text('CURRENT INSTRUCTION', style: TextStyle(color: _tealAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Text(
                _currentInstruction,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 32),
            const Text('BIOMETRIC PROGRESS', style: TextStyle(color: _tealAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildCheckmark('front', 'Front'),
                _buildCheckmark('side_left', 'Left'),
                _buildCheckmark('side_right', 'Right'),
                _buildCheckmark('angled_up', 'Up'),
                _buildCheckmark('angled_down', 'Down'),
              ],
            ),
            const Spacer(),
            if (_isComplete)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 12),
                    Text('Biometric Profile Completed', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
