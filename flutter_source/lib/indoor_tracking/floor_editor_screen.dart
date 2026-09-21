import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../network/api_routes.dart';
import '../network/network_manager.dart';

/// Simplified tap-based floor map editor: set a floor's real-world
/// dimensions and image, tap to place Wi-Fi APs and draw simple polygon
/// rooms, then publish. Intentionally not a CAD-grade vector tool — that
/// scope is out of bounds for v1 (see the approved plan's known
/// limitations); rectangular/simple clinic rooms like the reference floor
/// plan are the target case.
class FloorEditorScreen extends StatefulWidget {
  const FloorEditorScreen({super.key});

  @override
  State<FloorEditorScreen> createState() => _FloorEditorScreenState();
}

class _FloorEditorScreenState extends State<FloorEditorScreen> {
  List<Map<String, dynamic>> _floors = [];
  Map<String, dynamic>? _floor;
  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _wifiAps = [];

  // Room-drawing state
  final List<Offset> _drawingPoints = [];
  bool _drawingRoom = false;
  String _roomType = 'room';

  final _nameController = TextEditingController();
  final _widthController = TextEditingController(text: '15.09');
  final _heightController = TextEditingController(text: '11.79');

  @override
  void initState() {
    super.initState();
    _loadFloors();
  }

  Future<void> _loadFloors() async {
    final resp = await NetworkManager.instance.get(ApiRoutes.indoorTrackingFloors);
    if (resp.statusCode == 200) {
      setState(() => _floors = (jsonDecode(resp.body) as List).cast<Map<String, dynamic>>());
    }
  }

  Future<void> _createFloor() async {
    // A single Building must exist first - create one on demand if needed.
    final buildingsResp = await NetworkManager.instance.get(ApiRoutes.indoorTrackingBuildings);
    List buildings = buildingsResp.statusCode == 200 ? jsonDecode(buildingsResp.body) : [];
    int buildingId;
    if (buildings.isEmpty) {
      final created = await NetworkManager.instance.post(
        '${ApiRoutes.indoorTrackingBuildings}?name=${Uri.encodeComponent("Main Building")}',
      );
      buildingId = jsonDecode(created.body)['id'];
    } else {
      buildingId = buildings.first['id'];
    }

    final resp = await NetworkManager.instance.post(
      ApiRoutes.indoorTrackingFloors,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'building_id': buildingId,
        'name': _nameController.text.isEmpty ? 'New Floor' : _nameController.text,
        'level': 0,
        'width_m': double.tryParse(_widthController.text) ?? 15.0,
        'height_m': double.tryParse(_heightController.text) ?? 11.0,
      }),
    );
    if (resp.statusCode == 200) {
      await _loadFloors();
      final id = jsonDecode(resp.body)['id'];
      final floor = _floors.firstWhere((f) => f['id'] == id);
      _selectFloor(floor);
    }
  }

  Future<void> _selectFloor(Map<String, dynamic> floor) async {
    setState(() {
      _floor = floor;
      _rooms = [];
      _wifiAps = [];
      _drawingPoints.clear();
      _drawingRoom = false;
    });
    final roomsResp = await NetworkManager.instance.get(ApiRoutes.indoorTrackingRooms(floor['id']));
    final apsResp = await NetworkManager.instance.get(ApiRoutes.indoorTrackingFloorWifiAps(floor['id']));
    if (mounted) {
      setState(() {
        if (roomsResp.statusCode == 200) _rooms = (jsonDecode(roomsResp.body) as List).cast<Map<String, dynamic>>();
        if (apsResp.statusCode == 200) _wifiAps = (jsonDecode(apsResp.body) as List).cast<Map<String, dynamic>>();
      });
    }
  }

  Future<void> _uploadImage() async {
    if (_floor == null) return;
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.single.bytes == null) return;

    final request = NetworkManager.instance.multipartRequest(
      'POST', ApiRoutes.indoorTrackingFloorplanImageUpload(_floor!['id']),
    );
    request.files.add(http.MultipartFile.fromBytes(
      'file', result.files.single.bytes!, filename: result.files.single.name,
    ));
    final streamed = await request.send();
    if (streamed.statusCode == 200) {
      await _loadFloors();
      final refreshed = _floors.firstWhere((f) => f['id'] == _floor!['id']);
      setState(() => _floor = refreshed);
    }
  }

  Future<void> _handleTap(Offset localMeters) async {
    if (_floor == null) return;
    if (_drawingRoom) {
      setState(() => _drawingPoints.add(localMeters));
      return;
    }
    // Not drawing a room -> tapping places a Wi-Fi AP (prompt for BSSID).
    final bssid = await _promptText('Wi-Fi AP BSSID', hint: 'AA:BB:CC:DD:EE:FF');
    if (bssid == null || bssid.isEmpty) return;
    final resp = await NetworkManager.instance.post(
      ApiRoutes.indoorTrackingWifiAps,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'floor_id': _floor!['id'], 'bssid': bssid, 'ssid': null,
        'x': localMeters.dx, 'y': localMeters.dy, 'coverage_radius_m': 8.0,
      }),
    );
    if (resp.statusCode == 200) {
      final apsResp = await NetworkManager.instance.get(ApiRoutes.indoorTrackingFloorWifiAps(_floor!['id']));
      if (apsResp.statusCode == 200) {
        setState(() => _wifiAps = (jsonDecode(apsResp.body) as List).cast<Map<String, dynamic>>());
      }
    }
  }

  Future<void> _finishRoom() async {
    if (_floor == null || _drawingPoints.length < 3) return;
    final name = await _promptText('Room name', hint: 'e.g. Exam 1');
    if (name == null || name.isEmpty) {
      setState(() { _drawingPoints.clear(); _drawingRoom = false; });
      return;
    }
    final resp = await NetworkManager.instance.post(
      ApiRoutes.indoorTrackingRooms(_floor!['id']),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name, 'room_type': _roomType,
        'polygon': _drawingPoints.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
        'is_restricted': _roomType == 'restricted',
      }),
    );
    if (resp.statusCode == 200) {
      final roomsResp = await NetworkManager.instance.get(ApiRoutes.indoorTrackingRooms(_floor!['id']));
      if (roomsResp.statusCode == 200) {
        setState(() => _rooms = (jsonDecode(roomsResp.body) as List).cast<Map<String, dynamic>>());
      }
    }
    setState(() { _drawingPoints.clear(); _drawingRoom = false; });
  }

  Future<void> _publish() async {
    if (_floor == null) return;
    final resp = await NetworkManager.instance.post(ApiRoutes.indoorTrackingPublishFloor(_floor!['id']));
    if (resp.statusCode == 200 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Floor published')));
    }
  }

  Future<String?> _promptText(String title, {String? hint}) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('Floor Map Editor'),
        actions: [
          if (_floor != null)
            TextButton.icon(onPressed: _publish, icon: const Icon(Icons.publish), label: const Text('Publish')),
        ],
      ),
      body: Row(
        children: [
          SizedBox(width: 280, child: _buildFloorList(scheme)),
          Expanded(child: _floor == null ? const Center(child: Text('Select or create a floor')) : _buildCanvas(scheme)),
        ],
      ),
    );
  }

  Widget _buildFloorList(ColorScheme scheme) {
    return Container(
      color: scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'New floor name')),
                Row(children: [
                  Expanded(child: TextField(controller: _widthController, decoration: const InputDecoration(labelText: 'Width (m)'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _heightController, decoration: const InputDecoration(labelText: 'Height (m)'))),
                ]),
                const SizedBox(height: 8),
                ElevatedButton(onPressed: _createFloor, child: const Text('Create Floor')),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView(
              children: _floors.map((f) => ListTile(
                title: Text(f['name']),
                subtitle: Text(f['published'] == true ? 'Published' : 'Draft'),
                selected: _floor?['id'] == f['id'],
                onTap: () => _selectFloor(f),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas(ColorScheme scheme) {
    final widthM = (_floor!['width_m'] as num).toDouble();
    final heightM = (_floor!['height_m'] as num).toDouble();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              OutlinedButton.icon(onPressed: _uploadImage, icon: const Icon(Icons.image), label: const Text('Upload Floor Image')),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _roomType,
                items: const [
                  DropdownMenuItem(value: 'room', child: Text('Room')),
                  DropdownMenuItem(value: 'corridor', child: Text('Corridor')),
                  DropdownMenuItem(value: 'entrance', child: Text('Entrance')),
                  DropdownMenuItem(value: 'restricted', child: Text('Restricted')),
                ],
                onChanged: (v) => setState(() => _roomType = v ?? 'room'),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => setState(() { _drawingRoom = !_drawingRoom; _drawingPoints.clear(); }),
                icon: Icon(_drawingRoom ? Icons.close : Icons.draw),
                label: Text(_drawingRoom ? 'Cancel drawing' : 'Draw room'),
              ),
              if (_drawingRoom && _drawingPoints.length >= 3) ...[
                const SizedBox(width: 12),
                ElevatedButton(onPressed: _finishRoom, child: const Text('Finish room')),
              ],
              const SizedBox(width: 12),
              Text(_drawingRoom
                  ? 'Tap to add corners, then Finish room.'
                  : 'Tap the map to place a Wi-Fi AP.'),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            final scale = constraints.maxWidth / widthM;
            final displayHeight = heightM * scale;
            return Center(
              child: SizedBox(
                width: constraints.maxWidth,
                height: displayHeight,
                child: GestureDetector(
                  onTapUp: (details) => _handleTap(Offset(details.localPosition.dx / scale, details.localPosition.dy / scale)),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _floor!['floorplan_image_path'] != null
                            ? Image.network(
                                ApiRoutes.indoorTrackingFloorplanImageUrl(_floor!['floorplan_image_path']),
                                headers: NetworkManager.instance.authHeaders(), fit: BoxFit.fill,
                                errorBuilder: (_, __, ___) => Container(color: scheme.surfaceContainer),
                              )
                            : Container(color: scheme.surfaceContainer),
                      ),
                      Positioned.fill(
                        child: CustomPaint(painter: _EditorPainter(_rooms, _wifiAps, _drawingPoints, scale)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _EditorPainter extends CustomPainter {
  final List<Map<String, dynamic>> rooms;
  final List<Map<String, dynamic>> wifiAps;
  final List<Offset> drawingPoints;
  final double scale;
  _EditorPainter(this.rooms, this.wifiAps, this.drawingPoints, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    for (final room in rooms) {
      final polygon = (room['polygon'] as List)
          .map((p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
          .toList();
      if (polygon.length < 3) continue;
      final path = Path()..moveTo(polygon[0].dx * scale, polygon[0].dy * scale);
      for (final p in polygon.skip(1)) {
        path.lineTo(p.dx * scale, p.dy * scale);
      }
      path.close();
      final restricted = room['is_restricted'] == true;
      canvas.drawPath(
        path,
        Paint()
          ..color = (restricted ? Colors.red : Colors.blueGrey).withValues(alpha: 0.08)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = (restricted ? Colors.red : Colors.blueGrey).withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    for (final ap in wifiAps) {
      final x = (ap['x'] as num).toDouble() * scale;
      final y = (ap['y'] as num).toDouble() * scale;
      canvas.drawCircle(Offset(x, y), 5, Paint()..color = Colors.blue);
      canvas.drawCircle(
        Offset(x, y),
        (ap['coverage_radius_m'] as num).toDouble() * scale,
        Paint()..color = Colors.blue.withValues(alpha: 0.1)..style = PaintingStyle.fill,
      );
    }

    if (drawingPoints.length >= 2) {
      final path = Path()..moveTo(drawingPoints[0].dx * scale, drawingPoints[0].dy * scale);
      for (final p in drawingPoints.skip(1)) {
        path.lineTo(p.dx * scale, p.dy * scale);
      }
      canvas.drawPath(path, Paint()..color = Colors.amber..style = PaintingStyle.stroke..strokeWidth = 2);
    }
    for (final p in drawingPoints) {
      canvas.drawCircle(Offset(p.dx * scale, p.dy * scale), 4, Paint()..color = Colors.amber);
    }
  }

  @override
  bool shouldRepaint(covariant _EditorPainter oldDelegate) => true;
}
