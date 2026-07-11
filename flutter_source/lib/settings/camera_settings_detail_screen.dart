import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../camera/camera_stream_view.dart';
import '../main.dart' show GlassCard, GlassBackground;
import '../network/api_routes.dart';
import '../network/network_manager.dart';
import 'camera_status_dot.dart';
import 'rbac_mapper_screen.dart';

class CameraSettingsDetailScreen extends StatefulWidget {
  final Map<String, dynamic> camera;
  const CameraSettingsDetailScreen({super.key, required this.camera});

  @override
  State<CameraSettingsDetailScreen> createState() =>
      _CameraSettingsDetailScreenState();
}

class _CameraSettingsDetailScreenState extends State<CameraSettingsDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isAiEnabled = false;

  // Camera Info
  late TextEditingController _nameCtrl;
  late TextEditingController _locCtrl;
  late TextEditingController _urlCtrl;
  bool _isSavingInfo = false;

  // ROIs
  List<Map<String, dynamic>> _savedRois = [];
  final List<Offset> _currentPolygon = [];
  String _selectedZone = 'ICU';
  final List<String> _zones = ['ICU', 'Operating Room', 'General Ward'];
  bool _isLoadingRois = false;

  // Rules
  List<Map<String, dynamic>> _rules = [];
  bool _isLoadingRules = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    _nameCtrl = TextEditingController(text: widget.camera['name']);
    _locCtrl = TextEditingController(text: widget.camera['location'] ?? '');
    _urlCtrl = TextEditingController(text: widget.camera['rtsp_url']);

    if (_locCtrl.text.isNotEmpty && !_zones.contains(_locCtrl.text)) {
      _zones.add(_locCtrl.text);
    }
    _selectedZone = _zones.first;

    _fetchROIs();
    _fetchRules();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameCtrl.dispose();
    _locCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  // --- API Calls ---

  Future<void> _fetchROIs() async {
    setState(() => _isLoadingRois = true);
    try {
      final resp = await NetworkManager.instance
          .get(ApiRoutes.cameraRois(widget.camera['id']));
      if (resp.statusCode == 200 && mounted) {
        final data = jsonDecode(resp.body) as List<dynamic>;
        setState(() {
          _savedRois = data.cast<Map<String, dynamic>>();
          _currentPolygon.clear();
        });
        _fetchRules();
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingRois = false);
  }

  Future<void> _saveROI(Size canvasSize) async {
    if (_currentPolygon.length < 3) return;

    final normalizedPoints = _currentPolygon
        .map((p) =>
            {'x': p.dx / canvasSize.width, 'y': p.dy / canvasSize.height})
        .toList();

    setState(() => _isLoadingRois = true);
    try {
      final resp = await NetworkManager.instance.post(
        ApiRoutes.cameraRois(widget.camera['id']),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'zone_name': _selectedZone,
          'points': jsonEncode(normalizedPoints),
        }),
      );
      if (resp.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('ROI saved!'), backgroundColor: Colors.teal));
        _fetchROIs();
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingRois = false);
  }

  Future<void> _deleteROI(int roiId) async {
    setState(() => _isLoadingRois = true);
    try {
      await NetworkManager.instance.delete(ApiRoutes.deleteCameraRoi(roiId));
      _fetchROIs();
    } catch (_) {}
    if (mounted) setState(() => _isLoadingRois = false);
  }

  Future<void> _fetchRules() async {
    setState(() => _isLoadingRules = true);
    try {
      final resp = await NetworkManager.instance.get(ApiRoutes.securityRules);
      if (resp.statusCode == 200 && mounted) {
        final allRules = (jsonDecode(resp.body) as List<dynamic>)
            .cast<Map<String, dynamic>>();
        setState(() {
          _rules = allRules;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingRules = false);
  }

  Future<void> _addRule(String text) async {
    try {
      await NetworkManager.instance.post(
        ApiRoutes.securityRules,
        body: jsonEncode({
          "target_area":
              _locCtrl.text.isNotEmpty ? _locCtrl.text : _nameCtrl.text,
          "rule_text": text,
        }),
      );
      _fetchRules();
    } catch (_) {}
  }

  Future<void> _deleteRule(int id) async {
    try {
      await NetworkManager.instance.delete(ApiRoutes.deleteSecurityRule(id));
      _fetchRules();
    } catch (_) {}
  }

  Future<void> _updateCameraInfo() async {
    setState(() => _isSavingInfo = true);
    try {
      final resp = await NetworkManager.instance.put(
        ApiRoutes.camera(widget.camera['id']),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': _nameCtrl.text,
          'location': _locCtrl.text.isEmpty ? null : _locCtrl.text,
          'rtsp_url': _urlCtrl.text,
          'ha_entity_id': widget.camera['ha_entity_id'],
        }),
      );
      if (resp.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Camera updated!'), backgroundColor: Colors.teal));
      }
    } catch (_) {}
    if (mounted) setState(() => _isSavingInfo = false);
  }

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('Manage: ${_nameCtrl.text}',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
        backgroundColor: Colors.white.withOpacity(0.6),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.teal),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(color: Colors.transparent)),
        ),
      ),
      body: GlassBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 900) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 5,
                        child: _buildFeedCard(),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 4,
                        child: _buildTabsArea(),
                      ),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      Flexible(
                        flex: 5,
                        child: _buildFeedCard(),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        flex: 5,
                        child: _buildTabsArea(),
                      ),
                    ],
                  );
                }
              },
            ),
          ),
        ),
      ),
      // ),
    );
  }

  Widget _buildFeedCard() {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                CameraStatusDot(cameraId: widget.camera['id']),
                const SizedBox(width: 8),
                const Text('Live View',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                const Spacer(),
                const Text('Test AI Rules',
                    style: TextStyle(color: Colors.white70)),
                Switch(
                  value: _isAiEnabled,
                  activeThumbColor: Colors.tealAccent,
                  onChanged: (val) {
                    setState(() => _isAiEnabled = val);
                  },
                ),
              ],
            ),
          ),
          Flexible(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: LayoutBuilder(builder: (context, constraints) {
                final canvasSize =
                    Size(constraints.maxWidth, constraints.maxHeight);
                return Stack(
                  children: [
                    Positioned.fill(
                      child: CameraStreamView(
                        cameraId: widget.camera['id'],
                        mode: _isAiEnabled ? 'ai' : 'manage',
                        fit: BoxFit.fill,
                      ),
                    ),
                    if (_tabController.index ==
                        0) // Only allow drawing when ROI tab is active
                      GestureDetector(
                        onTapDown: (details) {
                          setState(() {
                            _currentPolygon.add(details.localPosition);
                          });
                        },
                        child: Container(
                          color: Colors.transparent,
                          width: double.infinity,
                          height: double.infinity,
                          child: CustomPaint(
                            painter: _ROIPainter(
                              savedRois: _savedRois,
                              currentPolygon: _currentPolygon,
                              currentZone: _selectedZone,
                            ),
                          ),
                        ),
                      ),
                    if (_tabController.index == 0 &&
                        _currentPolygon.length >= 3)
                      Positioned(
                        bottom: 16,
                        right: 16,
                        child: ElevatedButton.icon(
                          onPressed: () => _saveROI(canvasSize),
                          icon: const Icon(Icons.save),
                          label: const Text('Save ROI'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white),
                        ),
                      ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
      // ),
    );
  }

  Widget _buildTabsArea() {
    return Column(
      children: [
// Tabs
        TabBar(
          controller: _tabController,
          labelColor: Colors.teal.shade800,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: Colors.teal,
          onTap: (_) => setState(() {}),
          tabs: const [
            Tab(icon: Icon(Icons.area_chart), text: 'ROI Mapping'),
            Tab(icon: Icon(Icons.rule), text: 'Security Rules'),
            Tab(icon: Icon(Icons.settings), text: 'Info & Connection'),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: GlassCard(
            padding: const EdgeInsets.all(16),
            child: TabBarView(
              controller: _tabController,
              physics:
                  const NeverScrollableScrollPhysics(), // disable swipe so drawing isn't interrupted
              children: [
                _buildROITab(),
                _buildRulesTab(),
                _buildInfoTab(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildROITab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
            'Draw zones on the live feed above to define Regions of Interest.',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('Assign new zone to:'),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: _selectedZone,
              items: _zones
                  .map((z) => DropdownMenuItem(value: z, child: Text(z)))
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedZone = val;
                    _currentPolygon.clear();
                  });
                }
              },
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setState(() => _currentPolygon.clear()),
              icon: const Icon(Icons.clear, color: Colors.red),
              label: const Text('Clear Drawing',
                  style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_savedRois.isNotEmpty) ...[
          const Text('Saved Zones (Visible on Feed):',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _savedRois
                .map((r) => Chip(
                      label: Text(r['zone_name'],
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                      backgroundColor: Colors.teal.withOpacity(0.8),
                      deleteIcon: const Icon(Icons.close,
                          color: Colors.white, size: 14),
                      onDeleted: () => _deleteROI(r['id']),
                    ))
                .toList(),
          ),
        ]
      ],
    );
  }

  Widget _buildRulesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('All Mapped Security Rules (System-wide)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Expanded(
          child: _isLoadingRules
              ? const Center(child: CircularProgressIndicator())
              : _rules.isEmpty
                  ? const Center(
                      child:
                          Text('No specific rules found. Global rules apply.'))
                  : ListView.builder(
                      itemCount: _rules.length,
                      itemBuilder: (ctx, i) {
                        final r = _rules[i];
                        return ListTile(
                          leading:
                              const Icon(Icons.security, color: Colors.teal),
                          title: Text(r['rule_text']),
                          subtitle: Text(
                              'Target Area: ${r['target_area'] ?? 'Global'}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteRule(r['id']),
                          ),
                        );
                      },
                    ),
        ),
        const Divider(),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          const RBACMapperScreen(initialRulesMode: true)));
              _fetchRules();
            },
            icon: const Icon(Icons.schema_rounded),
            label: const Text('Go to Access Node Mapper (Security Rules)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Camera Name')),
          const SizedBox(height: 12),
          TextField(
              controller: _locCtrl,
              decoration: const InputDecoration(labelText: 'Location')),
          const SizedBox(height: 12),
          TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(labelText: 'RTSP URL')),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSavingInfo ? null : _updateCameraInfo,
              icon: const Icon(Icons.save),
              label:
                  Text(_isSavingInfo ? 'Saving...' : 'Update Connection Info'),
            ),
          )
        ],
      ),
    );
  }
}

class _ROIPainter extends CustomPainter {
  final List<Map<String, dynamic>> savedRois;
  final List<Offset> currentPolygon;
  final String currentZone;

  _ROIPainter({
    required this.savedRois,
    required this.currentPolygon,
    required this.currentZone,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw saved ROIs
    for (final roi in savedRois) {
      try {
        final pointsJson = jsonDecode(roi['points'] as String) as List<dynamic>;
        if (pointsJson.isEmpty) continue;

        final path = Path();
        for (int i = 0; i < pointsJson.length; i++) {
          final pt = pointsJson[i] as Map<String, dynamic>;
          final dx = (pt['x'] as num).toDouble() * size.width;
          final dy = (pt['y'] as num).toDouble() * size.height;
          if (i == 0) {
            path.moveTo(dx, dy);
          } else {
            path.lineTo(dx, dy);
          }
        }
        path.close();

        final fillPaint = Paint()
          ..color = Colors.orange.withOpacity(0.3)
          ..style = PaintingStyle.fill;
        canvas.drawPath(path, fillPaint);

        final strokePaint = Paint()
          ..color = Colors.orangeAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawPath(path, strokePaint);

        final tp = TextPainter(
          text: TextSpan(
              text: ' ${roi['zone_name']} ',
              style: const TextStyle(
                  color: Colors.white,
                  backgroundColor: Colors.orange,
                  fontSize: 10,
                  fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        final firstPt = pointsJson[0] as Map<String, dynamic>;
        tp.paint(
            canvas,
            Offset((firstPt['x'] as num).toDouble() * size.width,
                (firstPt['y'] as num).toDouble() * size.height - 15));
      } catch (e) {
        print('Error drawing ROI $roi: $e');
      }
    }

    // Current polygon
    if (currentPolygon.isNotEmpty) {
      final path = Path();
      path.moveTo(currentPolygon[0].dx, currentPolygon[0].dy);
      for (int i = 1; i < currentPolygon.length; i++) {
        path.lineTo(currentPolygon[i].dx, currentPolygon[i].dy);
      }

      if (currentPolygon.length >= 3) {
        path.close();
        final fillPaint = Paint()
          ..color = Colors.teal.withOpacity(0.4)
          ..style = PaintingStyle.fill;
        canvas.drawPath(path, fillPaint);
      }

      final strokePaint = Paint()
        ..color = Colors.tealAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawPath(path, strokePaint);

      final vertexPaint = Paint()..color = Colors.white;
      for (var p in currentPolygon) {
        canvas.drawCircle(p, 5, vertexPaint);
      }

      final tp = TextPainter(
        text: TextSpan(
            text: 'Drawing: $currentZone',
            style: const TextStyle(
                color: Colors.black,
                backgroundColor: Colors.tealAccent,
                fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(currentPolygon[0].dx, currentPolygon[0].dy - 20));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
