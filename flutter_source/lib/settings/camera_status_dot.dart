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
    switch (_status) {
      case 'online':
        color = Colors.green;
        break;
      case 'offline':
        color = Colors.red;
        break;
      default:
        color = Colors.orange;
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
      ),
    );
  }
}
