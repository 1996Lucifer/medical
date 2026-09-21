import 'dart:convert';
import 'package:flutter/material.dart';
import '../network/api_routes.dart';
import '../network/network_manager.dart';
import 'indoor_tracking_ws_client.dart';

class _FloorInfo {
  final int id;
  final String name;
  final double widthM;
  final double heightM;
  final String? floorplanImagePath;
  _FloorInfo({required this.id, required this.name, required this.widthM, required this.heightM, this.floorplanImagePath});
  factory _FloorInfo.fromJson(Map<String, dynamic> j) => _FloorInfo(
        id: j['id'], name: j['name'], widthM: (j['width_m'] as num).toDouble(),
        heightM: (j['height_m'] as num).toDouble(), floorplanImagePath: j['floorplan_image_path'],
      );
}

class _RoomInfo {
  final String name;
  final String roomType;
  final bool isRestricted;
  final List<Offset> polygon;
  _RoomInfo({required this.name, required this.roomType, required this.isRestricted, required this.polygon});
  factory _RoomInfo.fromJson(Map<String, dynamic> j) => _RoomInfo(
        name: j['name'], roomType: j['room_type'], isRestricted: j['is_restricted'] ?? false,
        polygon: (j['polygon'] as List)
            .map((p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
            .toList(),
      );
}

class IndoorTrackingScreen extends StatefulWidget {
  const IndoorTrackingScreen({super.key});

  @override
  State<IndoorTrackingScreen> createState() => _IndoorTrackingScreenState();
}

class _IndoorTrackingScreenState extends State<IndoorTrackingScreen> {
  List<_FloorInfo> _floors = [];
  List<_RoomInfo> _rooms = [];
  _FloorInfo? _selectedFloor;
  IndoorTrackingWsClient? _ws;
  String _search = '';
  int? _selectedSessionId;

  @override
  void initState() {
    super.initState();
    _loadFloors();
  }

  @override
  void dispose() {
    _ws?.stop();
    super.dispose();
  }

  Future<void> _loadFloors() async {
    try {
      final resp = await NetworkManager.instance.get(ApiRoutes.indoorTrackingPublishedFloors);
      if (resp.statusCode != 200) return;
      final floors = (jsonDecode(resp.body) as List).map((e) => _FloorInfo.fromJson(e)).toList();
      if (!mounted) return;
      setState(() => _floors = floors);
      if (floors.isNotEmpty) {
        _selectFloor(floors.first);
      }
    } catch (e) {
      debugPrint('[IndoorTracking] load floors failed: $e');
    }
  }

  Future<void> _selectFloor(_FloorInfo floor) async {
    _ws?.stop();
    setState(() {
      _selectedFloor = floor;
      _rooms = [];
      _selectedSessionId = null;
    });

    try {
      final resp = await NetworkManager.instance.get(ApiRoutes.indoorTrackingViewRooms(floor.id));
      if (resp.statusCode == 200) {
        final rooms = (jsonDecode(resp.body) as List).map((e) => _RoomInfo.fromJson(e)).toList();
        if (mounted) setState(() => _rooms = rooms);
      }
    } catch (e) {
      debugPrint('[IndoorTracking] load rooms failed: $e');
    }

    _ws = IndoorTrackingWsClient(floor.id)..start();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // MainShell's own top bar + bottom nav tab label already convey
    // "what app / what section" on mobile, so the title text here is
    // redundant - but the floor-picker dropdown is a real, needed action
    // (not just chrome), so the AppBar itself stays, just without a title.
    final isMobile = MediaQuery.of(context).size.width < 900;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: isMobile ? null : const Text('Indoor Location Tracking'),
        actions: [
          if (_floors.length > 1 || _floors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: DropdownButton<int>(
                value: _selectedFloor?.id,
                dropdownColor: scheme.surfaceContainerHigh,
                underline: const SizedBox.shrink(),
                items: _floors
                    .map((f) => DropdownMenuItem(value: f.id, child: Text(f.name)))
                    .toList(),
                onChanged: (id) {
                  final f = _floors.firstWhere((f) => f.id == id);
                  _selectFloor(f);
                },
              ),
            ),
        ],
      ),
      body: _floors.isEmpty
          ? const Center(child: Text('No published floors yet. Configure one in the Floor Editor.'))
          : Row(
              children: [
                Expanded(flex: 3, child: _buildMap(scheme)),
                SizedBox(
                  width: 320,
                  child: _buildSidePanel(scheme),
                ),
              ],
            ),
    );
  }

  Widget _buildMap(ColorScheme scheme) {
    final floor = _selectedFloor;
    if (floor == null || _ws == null) return const SizedBox.shrink();

    return LayoutBuilder(builder: (context, constraints) {
      final scale = constraints.maxWidth / floor.widthM;
      final displayHeight = floor.heightM * scale;

      return SingleChildScrollView(
        child: SizedBox(
          width: constraints.maxWidth,
          height: displayHeight,
          child: ValueListenableBuilder<Map<int, TrackedUser>>(
            valueListenable: _ws!.users,
            builder: (context, users, _) {
              final visible = users.values
                  .where((u) => u.status != 'stopped')
                  .where((u) => _search.isEmpty || u.staffName.toLowerCase().contains(_search.toLowerCase()))
                  .toList();

              return Stack(
                children: [
                  Positioned.fill(
                    child: floor.floorplanImagePath != null
                        ? Image.network(
                            ApiRoutes.indoorTrackingFloorplanImageUrl(floor.floorplanImagePath!),
                            headers: NetworkManager.instance.authHeaders(),
                            fit: BoxFit.fill,
                            errorBuilder: (_, __, ___) => Container(color: scheme.surfaceContainer),
                          )
                        : Container(color: scheme.surfaceContainer),
                  ),
                  Positioned.fill(
                    child: CustomPaint(painter: _RoomPainter(_rooms, scale)),
                  ),
                  for (final u in visible)
                    if (u.x != null && u.y != null) _buildMarker(u, scale, scheme),
                ],
              );
            },
          ),
        ),
      );
    });
  }

  Widget _buildMarker(TrackedUser u, double scale, ColorScheme scheme) {
    final cx = u.x! * scale;
    final cy = u.y! * scale;
    final radiusPx = (u.accuracyM ?? 3.0) * scale;
    final paused = u.status == 'paused_outside_geofence';
    final stale = u.isStale;
    final dim = paused || stale;

    final color = dim ? Colors.grey : (u.attendanceSessionId == _selectedSessionId ? Colors.amber : Colors.teal);

    // Status is distinguishable by shape/fill, not just color: active is a
    // solid filled dot, paused shows a dashed outer ring around a hollow
    // (unfilled) inner dot, stale shows a smaller, faded inner dot.
    final innerSize = stale ? 10.0 : 14.0;

    return Positioned(
      left: cx - radiusPx,
      top: cy - radiusPx,
      width: radiusPx * 2,
      height: radiusPx * 2,
      child: GestureDetector(
        onTap: () => setState(() => _selectedSessionId = u.attendanceSessionId),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (paused)
              CustomPaint(
                painter: _DashedCirclePainter(
                    color: color.withValues(alpha: 0.7)),
                size: Size(radiusPx * 2, radiusPx * 2),
              )
            else
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.15),
                  border: Border.all(color: color.withValues(alpha: dim ? 0.4 : 0.8)),
                ),
              ),
            Container(
              width: innerSize,
              height: innerSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: paused ? Colors.transparent : color.withValues(alpha: stale ? 0.6 : 1),
                border: Border.all(
                    color: paused ? color : Colors.white,
                    width: paused ? 2 : 2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidePanel(ColorScheme scheme) {
    if (_ws == null) return const SizedBox.shrink();
    return ValueListenableBuilder<Map<int, TrackedUser>>(
      valueListenable: _ws!.users,
      builder: (context, users, _) {
        final active = users.values.where((u) => u.status != 'stopped').toList()
          ..sort((a, b) => a.staffName.compareTo(b.staffName));
        final filtered = _search.isEmpty
            ? active
            : active.where((u) => u.staffName.toLowerCase().contains(_search.toLowerCase())).toList();

        TrackedUser? selected;
        for (final u in active) {
          if (u.attendanceSessionId == _selectedSessionId) {
            selected = u;
            break;
          }
        }

        return Container(
          color: scheme.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search user...',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('${active.length} active on this floor',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              const Divider(height: 24),
              if (selected != null) _buildDetailCard(selected, scheme),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final u = filtered[i];
                    return ListTile(
                      dense: true,
                      selected: u.attendanceSessionId == _selectedSessionId,
                      onTap: () => setState(() => _selectedSessionId = u.attendanceSessionId),
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: _statusColor(u).withValues(alpha: 0.2),
                        child: Icon(Icons.person, size: 14, color: _statusColor(u)),
                      ),
                      title: Text(u.staffName, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(u.areaName ?? '—', style: const TextStyle(fontSize: 11)),
                      trailing: _statusChip(u),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _statusColor(TrackedUser u) {
    if (u.status == 'paused_outside_geofence') return Colors.orange;
    if (u.isStale) return Colors.grey;
    return Colors.teal;
  }

  Widget _statusChip(TrackedUser u) {
    final label = u.status == 'paused_outside_geofence' ? 'Paused' : (u.isStale ? 'Stale' : 'Active');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _statusColor(u).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 9, color: _statusColor(u), fontWeight: FontWeight.w700)),
    );
  }

  Widget _buildDetailCard(TrackedUser u, ColorScheme scheme) {
    String hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
    String confidenceLabel(double? c) {
      if (c == null) return 'Unknown';
      if (c >= 0.75) return 'High';
      if (c >= 0.45) return 'Medium';
      return 'Low';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('USER #${u.staffId ?? '?'}', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant, letterSpacing: 1)),
          Text(u.staffName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          _kv('Department', u.department ?? '—'),
          _kv('Floor', _selectedFloor?.name ?? '—'),
          _kv('Area', u.areaName ?? 'Unknown'),
          _kv('Accuracy', u.accuracyM != null ? '~${u.accuracyM!.toStringAsFixed(1)} m' : '—'),
          _kv('Confidence', confidenceLabel(u.confidence)),
          _kv('Updated', hm(u.updatedAt.toLocal())),
          _kv('Tracking', u.status == 'paused_outside_geofence' ? 'Paused (outside premises)' : 'Active'),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 80, child: Text(k, style: const TextStyle(fontSize: 11, color: Colors.grey))),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          ],
        ),
      );
}

class _RoomPainter extends CustomPainter {
  final List<_RoomInfo> rooms;
  final double scale;
  _RoomPainter(this.rooms, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    for (final room in rooms) {
      if (room.polygon.length < 3) continue;
      final path = Path()..moveTo(room.polygon[0].dx * scale, room.polygon[0].dy * scale);
      for (final p in room.polygon.skip(1)) {
        path.lineTo(p.dx * scale, p.dy * scale);
      }
      path.close();

      final fillColor = room.isRestricted
          ? Colors.red.withValues(alpha: 0.08)
          : Colors.blueGrey.withValues(alpha: 0.04);
      final strokeColor = room.isRestricted ? Colors.red.withValues(alpha: 0.5) : Colors.blueGrey.withValues(alpha: 0.4);

      canvas.drawPath(path, Paint()..color = fillColor..style = PaintingStyle.fill);
      canvas.drawPath(path, Paint()..color = strokeColor..style = PaintingStyle.stroke..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(covariant _RoomPainter oldDelegate) => oldDelegate.rooms != rooms;
}

/// Dashed-border ring used for the "paused" marker state, so paused users
/// are distinguishable from active/stale ones by outline style, not just
/// color.
class _DashedCirclePainter extends CustomPainter {
  final Color color;
  _DashedCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    const dashLength = 4.0;
    const gapLength = 3.0;
    final circumference = 2 * 3.141592653589793 * radius;
    final dashCount = (circumference / (dashLength + gapLength)).floor();
    final anglePerDash = (2 * 3.141592653589793) / dashCount;
    final dashAngle = anglePerDash * (dashLength / (dashLength + gapLength));

    for (var i = 0; i < dashCount; i++) {
      final startAngle = i * anglePerDash;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
          startAngle, dashAngle, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) =>
      oldDelegate.color != color;
}
