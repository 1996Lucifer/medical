import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_router.dart';
import '../network/api_routes.dart';
import '../network/network_manager.dart';
import 'camera_status_dot.dart';
import 'manage_staff_screen.dart' show DashedRectPainter;

class CameraManagementScreen extends StatefulWidget {
  const CameraManagementScreen({super.key});

  @override
  State<CameraManagementScreen> createState() => _CameraManagementScreenState();
}

class _CameraManagementScreenState extends State<CameraManagementScreen> {
  List<Map<String, dynamic>> _savedCameras = [];

  // Theme-derived colors
  Color get _bgBase => Theme.of(context).scaffoldBackgroundColor;
  Color get _surfaceContainer => Theme.of(context).colorScheme.surfaceContainer;
  Color get _surfaceContainerLow =>
      Theme.of(context).colorScheme.surfaceContainerLow;
  Color get _tealAccent => Theme.of(context).colorScheme.secondary;
  Color get _textColor => Theme.of(context).colorScheme.onSurface;
  Color get _textVariant => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _critical => Theme.of(context).colorScheme.error;
  Color get _hairline => Theme.of(context).colorScheme.outlineVariant;

  @override
  void initState() {
    super.initState();
    _fetchCameras();
  }

  Future<void> _fetchCameras() async {
    try {
      final resp = await NetworkManager.instance
          .get(ApiRoutes.cameras)
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200 && mounted) {
        setState(() {
          _savedCameras = (jsonDecode(resp.body) as List<dynamic>)
              .cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {}
  }

  Future<void> _showAddCameraDialog() async {
    final nameCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final ipCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: '554');
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final pathCtrl = TextEditingController();
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => Theme(
        data: Theme.of(context).copyWith(
          scaffoldBackgroundColor: _bgBase,
          dialogTheme: DialogThemeData(backgroundColor: _surfaceContainer),
        ),
        child: StatefulBuilder(builder: (ctx, setD) {
          final ip = ipCtrl.text.trim();
          final port =
              portCtrl.text.trim().isEmpty ? '554' : portCtrl.text.trim();
          final user = userCtrl.text.trim();
          final pass = passCtrl.text.trim();
          var path = pathCtrl.text.trim();
          if (path.isNotEmpty && !path.startsWith('/')) path = '/$path';
          final creds =
              (user.isNotEmpty || pass.isNotEmpty) ? '$user:$pass@' : '';
          final previewUrl = ip.isEmpty
              ? 'rtsp://[ip]:[port]/[path]'
              : 'rtsp://$creds$ip:$port$path';

          return AlertDialog(
            title: Text('Add Camera',
                style: TextStyle(color: _textColor)),
            content: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                        controller: nameCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Camera Name')),
                    const SizedBox(height: 10),
                    TextField(
                        controller: locationCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Deployment Zone (optional)')),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: ipCtrl,
                            onChanged: (_) => setD(() {}),
                            decoration: const InputDecoration(
                                labelText: 'IP Address / Host',
                                hintText: '192.168.1.100'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: portCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setD(() {}),
                            decoration: const InputDecoration(
                                labelText: 'Port', hintText: '554'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: userCtrl,
                            onChanged: (_) => setD(() {}),
                            decoration: const InputDecoration(
                                labelText: 'Username (optional)'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: passCtrl,
                            obscureText: true,
                            onChanged: (_) => setD(() {}),
                            decoration: const InputDecoration(
                                labelText: 'Password (optional)'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: pathCtrl,
                      onChanged: (_) => setD(() {}),
                      decoration: const InputDecoration(
                          labelText: 'Stream Path (optional)',
                          hintText: '/h264Preview_01_main'),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _bgBase,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: Colors.teal.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('GENERATED RTSP URL PREVIEW',
                              style: TextStyle(
                                  color: _textVariant,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(previewUrl,
                              style: TextStyle(
                                  color: _tealAccent,
                                  fontFamily: 'monospace',
                                  fontSize: 11)),
                        ],
                      ),
                    ),
                    if (isSaving) ...[
                      const SizedBox(height: 12),
                      Center(
                          child: CircularProgressIndicator(color: _tealAccent))
                    ],
                  ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: _textVariant))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _tealAccent, foregroundColor: _bgBase),
                onPressed: isSaving
                    ? null
                    : () async {
                        if (nameCtrl.text.isEmpty || ipCtrl.text.isEmpty) {
                          return;
                        }
                        setD(() => isSaving = true);
                        final resp = await NetworkManager.instance.post(
                          ApiRoutes.cameras,
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({
                            'name': nameCtrl.text,
                            'location': locationCtrl.text.isEmpty
                                ? null
                                : locationCtrl.text,
                            'ip_address': ipCtrl.text.trim(),
                            'port': int.tryParse(portCtrl.text.trim()) ?? 554,
                            'username': userCtrl.text.isEmpty
                                ? null
                                : userCtrl.text.trim(),
                            'password': passCtrl.text.isEmpty
                                ? null
                                : passCtrl.text.trim(),
                            'stream_path': pathCtrl.text.isEmpty
                                ? null
                                : pathCtrl.text.trim(),
                          }),
                        );
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          if (resp.statusCode == 200) await _fetchCameras();
                        }
                      },
                child: const Text('Save Node'),
              ),
            ],
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgBase,
      appBar: AppBar(
        title: Text('Camera Node Management',
            style:
                TextStyle(color: _textColor, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: _textColor),
        // Reached via context.go(), which replaces the whole route stack —
        // there's nothing for the default back button to pop to, so it's
        // spelled out explicitly instead.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/settings'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildOverviewHeader(),
              const SizedBox(height: 24),
              _buildCameraGrid(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Active Node Registry',
                  style: TextStyle(
                      color: _textColor,
                      fontSize: 24,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                  'Centralized control for high-bandwidth RTSP surveillance assets. All feeds are currently routed through the local encryption layer.',
                  style: TextStyle(color: _textVariant, fontSize: 14)),
            ],
          ),
        ),
        const SizedBox(width: 32),
        Row(
          children: [
            _buildStatBox('Managed', '${_savedCameras.length}', _tealAccent),
            const SizedBox(width: 16),
            _buildStatBox('Faults', '0', _critical, isError: true),
          ],
        )
      ],
    );
  }

  Widget _buildStatBox(String label, String value, Color color,
      {bool isError = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isError ? color.withValues(alpha: 0.3) : _hairline),
      ),
      child: Column(
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: isError ? color : _textColor,
                  fontSize: 28,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _openAnalytics(int cameraId) {
    // go() (not push()) so the URL actually reflects the camera being
    // managed. This screen remounts fresh — and refetches — whenever the
    // detail screen navigates back here via context.go, so there's no
    // need to await a result to know when to refresh.
    context.go('$settingsCamerasPath/$cameraId');
  }

  Widget _buildCameraGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _savedCameras.length + 1,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        mainAxisExtent: 184,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemBuilder: (context, i) {
        if (i == 0) return _buildAddCameraCard();
        return _buildCameraCard(_savedCameras[i - 1]);
      },
    );
  }

  Widget _buildAddCameraCard() {
    return InkWell(
      onTap: _showAddCameraDialog,
      borderRadius: BorderRadius.circular(16),
      child: CustomPaint(
        painter: DashedRectPainter(
          color: _textVariant.withValues(alpha: 0.12),
          strokeWidth: 2,
          gap: 6,
          dash: 6,
          radius: 16,
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _surfaceContainer,
                ),
                child: Icon(Icons.add, size: 28, color: _textVariant),
              ),
              const SizedBox(height: 14),
              Text('Add Camera',
                  style: TextStyle(
                      color: _textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
              const SizedBox(height: 6),
              Text('Register a new RTSP surveillance node.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _textVariant, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraCard(Map<String, dynamic> c) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: _surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _hairline)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: _tealAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.videocam, color: _tealAccent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(c['name'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: _textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
              ),
              const SizedBox(width: 8),
              CameraStatusDot(cameraId: c['id'] as int, size: 8),
            ],
          ),
          const SizedBox(height: 12),
          Text(c['location'] ?? 'Unassigned',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _textVariant, fontSize: 13)),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.settings, size: 16),
              label: const Text('Manage'),
              onPressed: () => _openAnalytics(c['id'] as int),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _tealAccent, foregroundColor: _bgBase),
            ),
          ),
        ],
      ),
    );
  }
}
