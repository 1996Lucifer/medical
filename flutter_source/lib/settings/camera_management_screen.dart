import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../main.dart' show GlassCard, GlassBackground;
import '../network/api_routes.dart';
import '../network/network_manager.dart';
import 'camera_status_dot.dart';
import '../camera/camera_stream_view.dart';
import 'camera_settings_detail_screen.dart';

class CameraManagementScreen extends StatefulWidget {
  const CameraManagementScreen({super.key});

  @override
  State<CameraManagementScreen> createState() => _CameraManagementScreenState();
}

class _CameraManagementScreenState extends State<CameraManagementScreen> {
  List<Map<String, dynamic>> _savedCameras = [];
  Map<String, dynamic>? _previewCamera;

  @override
  void initState() {
    super.initState();
    _fetchCameras();
  }

  Future<void> _fetchCameras() async {
    try {
      final resp = await NetworkManager.instance.get(ApiRoutes.cameras).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200 && mounted) {
        setState(() {
          _savedCameras = (jsonDecode(resp.body) as List<dynamic>).cast<Map<String, dynamic>>();
        });
      }
    } catch (_) {}
  }

  Future<void> _deleteCamera(Map<String, dynamic> c) async {
    final resp = await NetworkManager.instance.delete(ApiRoutes.camera(c['id']));
    if (resp.statusCode != 200 && mounted) {
      String errorMsg = 'Failed to delete camera.';
      try {
        errorMsg = jsonDecode(resp.body)['detail'] ?? errorMsg;
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMsg), backgroundColor: Colors.red));
    } else {
      if (_previewCamera?['id'] == c['id']) setState(() => _previewCamera = null);
      await _fetchCameras();
    }
  }

  Future<void> _showAddCameraDialog() async {
    final nameCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          title: const Text('Add Camera Source'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Camera Name')),
              const SizedBox(height: 10),
              TextField(controller: locationCtrl, decoration: const InputDecoration(labelText: 'Location (optional)')),
              const SizedBox(height: 10),
              TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'RTSP URL')),
              if (isSaving) ...[const SizedBox(height: 12), const CircularProgressIndicator()],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: isSaving ? null : () async {
                if (nameCtrl.text.isEmpty || urlCtrl.text.isEmpty) return;
                setD(() => isSaving = true);
                final resp = await NetworkManager.instance.post(
                  ApiRoutes.cameras,
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'name': nameCtrl.text,
                    'location': locationCtrl.text.isEmpty ? null : locationCtrl.text,
                    'rtsp_url': urlCtrl.text,
                  }),
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  if (resp.statusCode == 200) await _fetchCameras();
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _showEditCameraDialog(Map<String, dynamic> c) async {
    final nameCtrl = TextEditingController(text: c['name']);
    final locationCtrl = TextEditingController(text: c['location'] ?? '');
    final urlCtrl = TextEditingController(text: c['rtsp_url']);
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          title: const Text('Edit Camera Source'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Camera Name')),
              const SizedBox(height: 10),
              TextField(controller: locationCtrl, decoration: const InputDecoration(labelText: 'Location (optional)')),
              const SizedBox(height: 10),
              TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'RTSP URL')),
              if (isSaving) ...[const SizedBox(height: 12), const CircularProgressIndicator()],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: isSaving ? null : () async {
                if (nameCtrl.text.isEmpty || urlCtrl.text.isEmpty) return;
                setD(() => isSaving = true);
                final resp = await NetworkManager.instance.put(
                  ApiRoutes.camera(c['id']),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'name': nameCtrl.text,
                    'location': locationCtrl.text.isEmpty ? null : locationCtrl.text,
                    'rtsp_url': urlCtrl.text,
                    'ha_entity_id': c['ha_entity_id'],
                  }),
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  if (resp.statusCode == 200) await _fetchCameras();
                }
              },
              child: const Text('Update'),
            ),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Manage Cameras', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
        backgroundColor: Colors.white.withOpacity(0.6),
        elevation: 0,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: Container(color: Colors.transparent)),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddCameraDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Camera'),
      ),
      body: GlassBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 800;

                final listWidget = GlassCard(
                  child: _savedCameras.isEmpty
                      ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No cameras saved.')))
                      : ListView.separated(
                          itemCount: _savedCameras.length,
                          separatorBuilder: (c, i) => const Divider(),
                          itemBuilder: (context, i) {
                            final c = _savedCameras[i];
                            final isSelected = _previewCamera?['id'] == c['id'];
                            return ListTile(
                              selected: isSelected,
                              selectedTileColor: Colors.teal.shade50,
                              leading: Stack(
                                alignment: Alignment.topRight,
                                children: [
                                  const Padding(padding: EdgeInsets.all(4.0), child: Icon(Icons.videocam)),
                                  CameraStatusDot(cameraId: c['id'] as int, size: 10),
                                ],
                              ),
                              title: Text(c['name']),
                              subtitle: Text(c['location'] ?? c['rtsp_url']),
                              onTap: () {
                                setState(() {
                                  _previewCamera = isSelected ? null : c;
                                });
                              },
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.grey),
                                    onPressed: () => _showEditCameraDialog(c),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    onPressed: () => _deleteCamera(c),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                );

                  final previewWidget = _previewCamera != null
                      ? GlassCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Live Preview: ${_previewCamera!['name']}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.settings, size: 16),
                                    label: const Text('Manage this Camera'),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => CameraSettingsDetailScreen(camera: _previewCamera!))
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.teal,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  clipBehavior: Clip.hardEdge,
                                  child: CameraStreamView(cameraId: _previewCamera!['id'], mode: 'manage'),
                                ),
                              ),
                            ],
                          ),
                        )
                      : const GlassCard(
                        child: Center(
                          child: Text('Select a camera to view live feed', style: TextStyle(color: Colors.grey)),
                        ),
                      );

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: listWidget),
                      const SizedBox(width: 16),
                      Expanded(flex: 3, child: previewWidget),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      if (_previewCamera != null)
                        SizedBox(height: 250, child: previewWidget),
                      if (_previewCamera != null) const SizedBox(height: 16),
                      Expanded(child: listWidget),
                    ],
                  );
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}
