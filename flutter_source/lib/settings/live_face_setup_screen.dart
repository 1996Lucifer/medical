import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../network/api_routes.dart';

class LiveFaceSetupScreen extends StatefulWidget {
  final int staffId;
  const LiveFaceSetupScreen({super.key, required this.staffId});

  @override
  State<LiveFaceSetupScreen> createState() => _LiveFaceSetupScreenState();
}

class _LiveFaceSetupScreenState extends State<LiveFaceSetupScreen> {
  CameraController? _controller;
  WebSocketChannel? _channel;
  Timer? _timer;
  List<CameraDescription> _cameras = [];
  int _currentCameraIndex = 0;

  bool _isInitializing = true;
  String _currentInstruction = "Connecting to AI Engine...";
  List<String> _completedAngles = [];
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
        if (_cameras.isEmpty) throw Exception('No cameras found');

        // Try to start with front camera if available
        _currentCameraIndex = _cameras
            .indexWhere((c) => c.lensDirection == CameraLensDirection.front);
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
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No other cameras found')));
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
          _completedAngles =
              (data['completed'] as List<dynamic>).cast<String>();

          if (data['status'] == 'complete') {
            _isComplete = true;
            _timer?.cancel();
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted)
                Navigator.pop(context, true); // true indicates success
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
      if (_isComplete ||
          _controller == null ||
          !_controller!.value.isInitialized ||
          _controller!.value.isTakingPicture) {
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
    _timer?.cancel();
    _channel?.sink.close();
    _controller?.dispose();
    super.dispose();
  }

  Widget _buildCheckmark(String angle, String label) {
    final isDone = _completedAngles.contains(angle);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDone
            ? Colors.green.withOpacity(0.2)
            : Colors.white.withOpacity(0.1),
        border: Border.all(
            color: isDone ? Colors.green.withOpacity(0.5) : Colors.transparent),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDone ? Icons.check_circle : Icons.circle_outlined,
            color: isDone ? Colors.green : Colors.white54,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: isDone ? Colors.green : Colors.white70,
              fontWeight: isDone ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Face ID Setup',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
            onPressed: _switchCamera,
            tooltip: 'Switch Camera',
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_controller != null && _controller!.value.isInitialized)
            Positioned.fill(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1 / _controller!.value.aspectRatio,
                  child: CameraPreview(_controller!),
                ),
              ),
            ),

          // Perfect circular face cutout overlay
          Positioned.fill(
            child: CustomPaint(
              painter: _FaceHolePainter(isComplete: _isComplete),
            ),
          ),

          // Instruction Overlay pill
          Positioned(
            top: 100,
            left: 20,
            right: 20,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Text(
                      _currentInstruction,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Progress Checklist (Glassmorphism card)
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Progress',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18)),
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.center,
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
                    ],
                  ),
                ),
              ),
            ),
          ),

          if (_isComplete)
            Container(
              color: Colors.black.withOpacity(0.85),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 80),
                    SizedBox(height: 16),
                    Text(
                      'Face ID Complete',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold),
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

class _FaceHolePainter extends CustomPainter {
  final bool isComplete;
  _FaceHolePainter({required this.isComplete});

  @override
  void paint(Canvas canvas, Size size) {
    // Dim the background lightly so the face cutout is visible but surroundings can be seen
    final paint = Paint()..color = Colors.black.withOpacity(0.45);

    // Create a circular/oval cutout that scales correctly but isn't too huge on tablets
    final shortestSide = size.width < size.height ? size.width : size.height;

    // Make the oval take up ~75% of the shortest side (matching the backend's 80% safe zone)
    final ovalWidth = shortestSide * 0.75;
    final ovalHeight = shortestSide *
        0.95; // Slightly taller than wide for a natural face shape

    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2.3),
      width: ovalWidth,
      height: ovalHeight,
    );

    // Combine outer rect and inner oval to create a hole
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
      Path()
        ..addOval(rect)
        ..close(),
    );
    canvas.drawPath(path, paint);

    // Draw an elegant Apple-style border around the hole
    final borderPaint = Paint()
      ..color = isComplete ? Colors.green : Colors.blueAccent.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawOval(rect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _FaceHolePainter oldDelegate) {
    return oldDelegate.isComplete != isComplete;
  }
}
