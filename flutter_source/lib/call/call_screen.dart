import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';

import 'call_models.dart';
import 'call_service.dart';

/// In-call UI for both audio and video calls - a single screen that adapts
/// based on CallService.mode, pushed by whichever screen initiates or
/// accepts a call (see IncomingCallDialog and the patient/doctor call
/// buttons). Pops itself once the call ends.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _renderersReady = false;
  bool _hasPopped = false;

  @override
  void initState() {
    super.initState();
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    if (mounted) setState(() => _renderersReady = true);
  }

  void _maybePop(CallService call) {
    if (_hasPopped) return;
    if (call.callState == CallState.ended) {
      _hasPopped = true;
      Future.microtask(() {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        call.resetToIdle();
      });
    }
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  String _statusText(CallState state) {
    switch (state) {
      case CallState.ringingOutgoing:
        return 'Calling...';
      case CallState.connecting:
        return 'Connecting...';
      case CallState.active:
        return 'Connected';
      case CallState.ended:
        return 'Call ended';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallService>();
    _maybePop(call);

    if (_renderersReady) {
      _localRenderer.srcObject = call.localStream;
      _remoteRenderer.srcObject = call.remoteStream;
    }

    final isVideo = call.mode == CallMode.video;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Remote video (or an avatar placeholder for audio calls / before
            // the remote video track arrives).
            Positioned.fill(
              child: isVideo && call.remoteStream != null && _renderersReady
                  ? RTCVideoView(_remoteRenderer,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : Container(
                      color: const Color(0xFF101828),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 56,
                              backgroundColor: scheme.secondary.withValues(alpha: 0.2),
                              child: Text(
                                (call.peer?.name.isNotEmpty == true
                                        ? call.peer!.name[0]
                                        : '?')
                                    .toUpperCase(),
                                style: TextStyle(
                                    fontSize: 40, color: scheme.secondary),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(call.peer?.name ?? '',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
            ),

            // Status banner
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusText(call.callState),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),

            // Local video PiP (video calls only)
            if (isVideo && call.localStream != null && _renderersReady)
              Positioned(
                top: 16,
                right: 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 100,
                    height: 140,
                    child: RTCVideoView(
                      _localRenderer,
                      mirror: true,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),

            // Controls
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _controlButton(
                    icon: call.micEnabled ? Icons.mic : Icons.mic_off,
                    onPressed: call.toggleMic,
                  ),
                  const SizedBox(width: 20),
                  _controlButton(
                    icon: Icons.call_end,
                    backgroundColor: Colors.redAccent,
                    onPressed: call.hangUp,
                    large: true,
                  ),
                  const SizedBox(width: 20),
                  if (isVideo)
                    _controlButton(
                      icon: call.cameraEnabled
                          ? Icons.videocam
                          : Icons.videocam_off,
                      onPressed: call.toggleCamera,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color backgroundColor = Colors.white24,
    bool large = false,
  }) {
    final size = large ? 64.0 : 52.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: large ? 30 : 24),
        onPressed: onPressed,
      ),
    );
  }
}
