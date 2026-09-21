import 'dart:convert';
import 'package:flutter/material.dart';
import '../network/api_routes.dart';
import '../network/network_manager.dart';

class CameraStatusDot extends StatefulWidget {
  final int cameraId;
  final double size;

  const CameraStatusDot({super.key, required this.cameraId, this.size = 12.0});

  @override
  State<CameraStatusDot> createState() => _CameraStatusDotState();
}

class _CameraStatusDotState extends State<CameraStatusDot> {
  String _status = 'loading'; // 'loading', 'online', 'offline'

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  @override
  void didUpdateWidget(CameraStatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cameraId != widget.cameraId) {
      _checkStatus();
    }
  }

  Future<void> _checkStatus() async {
    setState(() => _status = 'loading');
    try {
      final resp = await NetworkManager.instance
          .get(ApiRoutes.cameraStatus(widget.cameraId));
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body);
        setState(() {
          _status = data['status'] == 'online' ? 'online' : 'offline';
        });
      } else if (mounted) {
        setState(() => _status = 'offline');
      }
    } catch (_) {
      if (mounted) setState(() => _status = 'offline');
    }
  }

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    switch (_status) {
      case 'online':
        color = Colors.green;
        icon = Icons.check;
        break;
      case 'offline':
        color = Colors.red;
        icon = Icons.close;
        break;
      default:
        color = Colors.orange;
        icon = Icons.hourglass_empty;
    }

    return Tooltip(
      message: _status == 'online'
          ? 'Stream Live'
          : (_status == 'loading'
              ? 'Checking stream...'
              : 'Stream Offline/Unreachable'),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 4,
                spreadRadius: 1),
          ],
        ),
        // Status is also conveyed by shape, not just dot color, so it
        // reads correctly for color-blind users: a check for online, an
        // X for offline, an hourglass while checking.
        child: Icon(icon, color: Colors.white, size: widget.size * 0.7),
      ),
    );
  }
}
