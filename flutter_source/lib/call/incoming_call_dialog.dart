import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_router.dart' show rootNavigatorKey;
import 'call_models.dart';
import 'call_screen.dart';
import 'call_service.dart';

/// Mounted once as a global overlay (see main.dart) so an incoming call can
/// surface over whatever screen the user is currently on. Renders nothing
/// when there's no incoming call; shows Accept/Decline while one is ringing;
/// pushes CallScreen once accepted.
class IncomingCallOverlay extends StatefulWidget {
  const IncomingCallOverlay({super.key});

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay> {
  bool _callScreenShown = false;
  String? _lastShownError;

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallService>();

    // CallService.lastError was being set in 4 places (camera/mic denied,
    // signaling failure, "unavailable", "denied") but never actually shown
    // anywhere - a failed call just silently dropped the user back with no
    // explanation, indistinguishable from the button doing nothing at all.
    // This is the one place mounted for the whole app session, so it's the
    // natural spot to surface it exactly once per failure.
    if (call.lastError != null && call.lastError != _lastShownError) {
      _lastShownError = call.lastError;
      final message = call.lastError!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
        );
      });
    } else if (call.lastError == null) {
      _lastShownError = null;
    }

    // Once a call becomes active/connecting (either because we accepted an
    // incoming call, or the far end accepted ours), make sure CallScreen is
    // on screen - covers both directions from one place.
    final shouldShowCallScreen = call.callState == CallState.connecting ||
        call.callState == CallState.active ||
        call.callState == CallState.ringingOutgoing;

    if (shouldShowCallScreen && !_callScreenShown) {
      _callScreenShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Can't use Navigator.of(context) here: this widget is mounted in
        // MaterialApp.router's `builder`, whose context sits ABOVE the
        // router's own Navigator, not inside it - go straight to the root
        // navigator key the app already wires up (see app_router.dart)
        // instead.
        final navigator = rootNavigatorKey.currentState;
        navigator
            ?.push(MaterialPageRoute(builder: (_) => const CallScreen()))
            .then((_) => _callScreenShown = false);
      });
    } else if (!shouldShowCallScreen && call.callState != CallState.ringingIncoming) {
      _callScreenShown = false;
    }

    if (call.callState != CallState.ringingIncoming) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.black54,
      child: Center(
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: scheme.secondary.withValues(alpha: 0.2),
                child: Icon(
                  call.mode == CallMode.video ? Icons.videocam : Icons.call,
                  color: scheme.secondary,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                call.peer?.name ?? 'Unknown',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                call.mode == CallMode.video ? 'Incoming video call' : 'Incoming call',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _actionButton(
                    icon: Icons.call_end,
                    color: Colors.redAccent,
                    onPressed: call.rejectIncomingCall,
                    tooltip: 'Decline call',
                  ),
                  _actionButton(
                    icon: Icons.call,
                    color: Colors.green,
                    onPressed: call.acceptIncomingCall,
                    tooltip: 'Accept call',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
  }
}
