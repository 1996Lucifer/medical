import 'dart:convert';
import 'package:flutter/material.dart';
import '../network/api_routes.dart';
import '../network/network_manager.dart';
import 'camera_status_dot.dart';
import '../camera/camera_stream_view.dart';
import 'camera_settings_detail_screen.dart';

const Color _bgBase = Color(0xFF041329);
const Color _surfaceContainer = Color(0xFF112036);
const Color _surfaceContainerLow = Color(0xFF0d1c32);
const Color _tealAccent = Color(0xFF64ffda);
const Color _textColor = Color(0xFFd6e3ff);
const Color _textVariant = Color(0xFFbacac3);
const Color _critical = Color(0xFFffb4ab);

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

  Future<void> _deleteCamera(Map<String, dynamic> c) async {
    final resp = await NetworkManager.instance.delete(ApiRoutes.camera(c['id']));
    if (resp.statusCode != 200 && mounted) {
      String errorMsg = 'Failed to delete camera.';
      try {
        errorMsg = jsonDecode(resp.body)['detail'] ?? errorMsg;
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.red));
    } else {
      if (_previewCamera?['id'] == c['id']) {
        setState(() => _previewCamera = null);
      }
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
      builder: (ctx) => Theme(
        data: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: _bgBase,
          dialogBackgroundColor: _surfaceContainer,
        ),
        child: StatefulBuilder(builder: (ctx, setD) {
          return AlertDialog(
            title: const Text('Register New Node', style: TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Camera Name')),
                const SizedBox(height: 10),
                TextField(
                    controller: locationCtrl,
                    decoration: const InputDecoration(labelText: 'Deployment Zone (optional)')),
                const SizedBox(height: 10),
                TextField(
                    controller: urlCtrl,
                    decoration: const InputDecoration(labelText: 'RTSP URL')),
                if (isSaving) ...[
                  const SizedBox(height: 12),
                  const CircularProgressIndicator(color: _tealAccent)
                ],
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: _textVariant))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _tealAccent, foregroundColor: _bgBase),
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
                child: const Text('Save Node'),
              ),
            ],
          );
        }),
      ),
    );
  }

  Future<void> _showEditCameraDialog(Map<String, dynamic> c) async {
    final nameCtrl = TextEditingController(text: c['name']);
    final locationCtrl = TextEditingController(text: c['location'] ?? '');
    final urlCtrl = TextEditingController(text: c['rtsp_url']);
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (ctx) => Theme(
        data: ThemeData.dark().copyWith(
          dialogBackgroundColor: _surfaceContainer,
        ),
        child: StatefulBuilder(builder: (ctx, setD) {
          return AlertDialog(
            title: const Text('Configure Node', style: TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Camera Name')),
                const SizedBox(height: 10),
                TextField(controller: locationCtrl, decoration: const InputDecoration(labelText: 'Deployment Zone')),
                const SizedBox(height: 10),
                TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'RTSP URL')),
                if (isSaving) ...[
                  const SizedBox(height: 12),
                  const CircularProgressIndicator(color: _tealAccent)
                ],
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: _textVariant))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _tealAccent, foregroundColor: _bgBase),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgBase,
      appBar: AppBar(
        title: const Text('Camera Node Management', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddCameraDialog,
        backgroundColor: _tealAccent,
        foregroundColor: _bgBase,
        icon: const Icon(Icons.add),
        label: const Text('Register New Node', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildOverviewHeader(),
              const SizedBox(height: 24),
              _buildDataTable(),
              const SizedBox(height: 24),
              _buildInfrastructureCards(),
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
            children: const [
              Text('Active Node Registry', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Centralized control for high-bandwidth RTSP surveillance assets. All feeds are currently routed through the Aegis Encryption Layer.', style: TextStyle(color: _textVariant, fontSize: 14)),
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

  Widget _buildStatBox(String label, String value, Color color, {bool isError = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: _surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isError ? color.withOpacity(0.3) : Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Text(label.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: isError ? color : Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDataTable() {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(_surfaceContainerLow),
              dataRowColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return _tealAccent.withOpacity(0.1);
                }
                return Colors.transparent;
              }),
              columns: const [
                DataColumn(label: Text('IDENTIFIER', style: TextStyle(color: _textVariant, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2))),
                DataColumn(label: Text('DEPLOYMENT ZONE', style: TextStyle(color: _textVariant, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2))),
                DataColumn(label: Text('STREAM CONFIGURATION', style: TextStyle(color: _textVariant, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2))),
                DataColumn(label: Text('LIVE STATUS', style: TextStyle(color: _textVariant, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2))),
                DataColumn(label: Text('OPERATIONS', style: TextStyle(color: _textVariant, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2))),
              ],
              rows: _savedCameras.map((c) {
                final isSelected = _previewCamera?['id'] == c['id'];
                return DataRow(
                  selected: isSelected,
                  onSelectChanged: (val) {
                    setState(() {
                      _previewCamera = isSelected ? null : c;
                    });
                  },
                  cells: [
                    DataCell(Text(c['name'] ?? '', style: const TextStyle(color: _tealAccent, fontFamily: 'monospace', fontWeight: FontWeight.bold))),
                    DataCell(Text(c['location'] ?? 'Unassigned', style: const TextStyle(color: Colors.white))),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: _bgBase, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white.withOpacity(0.1))),
                        child: Text(c['rtsp_url'] ?? '', style: const TextStyle(color: _textVariant, fontFamily: 'monospace', fontSize: 11)),
                      ),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CameraStatusDot(cameraId: c['id'] as int, size: 10),
                          const SizedBox(width: 8),
                          const Text('Operational', style: TextStyle(color: _tealAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      )
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: const Icon(Icons.videocam, color: Colors.white54, size: 20), onPressed: () {
                            setState(() => _previewCamera = c);
                          }),
                          IconButton(icon: const Icon(Icons.settings, color: Colors.white54, size: 20), onPressed: () => _showEditCameraDialog(c)),
                          IconButton(icon: const Icon(Icons.delete_outline, color: _critical, size: 20), onPressed: () => _deleteCamera(c)),
                        ],
                      )
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          if (_previewCamera != null) ...[
             const Divider(color: Colors.white24, height: 1),
             _buildLivePreview(),
          ]
        ],
      ),
    );
  }

  Widget _buildLivePreview() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Live Preview: ${_previewCamera!['name']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ElevatedButton.icon(
                icon: const Icon(Icons.settings, size: 16),
                label: const Text('Manage Analytics'),
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => CameraSettingsDetailScreen(camera: _previewCamera!)));
                },
                style: ElevatedButton.styleFrom(backgroundColor: _tealAccent, foregroundColor: _bgBase),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 400,
            child: Container(
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.1))),
              clipBehavior: Clip.hardEdge,
              child: CameraStreamView(cameraId: _previewCamera!['id'], mode: 'manage'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfrastructureCards() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: _surfaceContainerLow, borderRadius: BorderRadius.circular(16), border: Border.all(color: _tealAccent.withOpacity(0.2))),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: _tealAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.security, color: _tealAccent),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Stream Integrity', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('System-wide AES-256 encryption is active.', style: TextStyle(color: _textVariant, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: _surfaceContainerLow, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.05))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Load Profile', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: _tealAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(4), border: Border.all(color: _tealAccent.withOpacity(0.2))), child: const Text('STABLE', style: TextStyle(color: _tealAccent, fontSize: 10, fontWeight: FontWeight.bold))),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: 0.42, backgroundColor: const Color(0xFF27354c), color: _tealAccent, minHeight: 6, borderRadius: BorderRadius.circular(3)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
