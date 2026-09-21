import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:turf/turf.dart' as turf;

import '../network/api_routes.dart';
import '../network/network_manager.dart';

/// Hospital premises geofence + working hours config. The boundary is
/// drawn directly on an interactive Mapbox map (mapbox_maps_flutter, the
/// official SDK - its 3.0.0-alpha line added a Flutter Web platform
/// implementation via mapbox_maps_flutter_web/Mapbox GL JS, which earlier
/// stable 2.x releases did not have). Tap the map to add a boundary point;
/// remove one from the list on the right.
///
/// Point markers are rendered as a GeoJSON source + CircleLayer, NOT via
/// CircleAnnotationManager - the annotation-manager plugin API is a stub on
/// web in this alpha (every method throws UnimplementedError there; see
/// mapbox_maps_flutter_web's circle_annotation_manager_web.dart). Plain
/// style sources/layers (addSource/addLayer/setStyleSourceProperty) ARE
/// implemented on web, so both the polygon and the points use that path.
class HospitalGeofenceScreen extends StatefulWidget {
  const HospitalGeofenceScreen({super.key});

  @override
  State<HospitalGeofenceScreen> createState() => _HospitalGeofenceScreenState();
}

class _HospitalGeofenceScreenState extends State<HospitalGeofenceScreen> {
  static const _polygonSourceId = 'hospital-geofence-source';
  static const _fillLayerId = 'hospital-geofence-fill';
  static const _lineLayerId = 'hospital-geofence-line';
  static const _pointsSourceId = 'hospital-geofence-points-source';
  static const _pointsLayerId = 'hospital-geofence-points';
  static final _defaultCenter =
      turf.Position(77.7104553, 29.1035953); // fallback: no saved geofence yet

  List<turf.Position> _points = [];
  final _startController = TextEditingController(text: '09:00');
  final _endController = TextEditingController(text: '18:00');
  bool _loaded = false;
  bool _styleReady = false;

  MapboxMap? _mapboxMap;
  final GlobalKey _mapKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final resp =
        await NetworkManager.instance.get(ApiRoutes.indoorTrackingHospital);
    if (resp.statusCode == 200 && resp.body != 'null') {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      setState(() {
        _points = (data['geofence_polygon'] as List)
            .map((p) => turf.Position(
                (p['lng'] as num).toDouble(), (p['lat'] as num).toDouble()))
            .toList();
        if (data['working_hours_start'] != null) {
          _startController.text =
              (data['working_hours_start'] as String).substring(0, 5);
        }
        if (data['working_hours_end'] != null) {
          _endController.text =
              (data['working_hours_end'] as String).substring(0, 5);
        }
        _loaded = true;
      });
    } else {
      setState(() => _loaded = true);
    }
  }

  turf.Position get _center =>
      _points.isNotEmpty ? _points.first : _defaultCenter;

  void _onMapCreated(MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
  }

  Future<void> _onStyleLoaded() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;

    await mapboxMap.addSource(GeoJsonSource(
        id: _polygonSourceId, data: jsonEncode(_polygonGeoJson())));
    await mapboxMap.addLayer(FillLayer(
      id: _fillLayerId,
      sourceId: _polygonSourceId,
      fillColor: Colors.teal.toARGB32(),
      fillOpacity: 0.15,
    ));
    await mapboxMap.addLayer(LineLayer(
      id: _lineLayerId,
      sourceId: _polygonSourceId,
      lineColor: Colors.teal.toARGB32(),
      lineWidth: 2.5,
    ));

    await mapboxMap.addSource(
        GeoJsonSource(id: _pointsSourceId, data: jsonEncode(_pointsGeoJson())));
    await mapboxMap.addLayer(CircleLayer(
      id: _pointsLayerId,
      sourceId: _pointsSourceId,
      circleColor: Colors.teal.toARGB32(),
      circleRadius: 6.0,
      circleStrokeColor: Colors.white.toARGB32(),
      circleStrokeWidth: 2.0,
    ));

    setState(() => _styleReady = true);
  }

  Map<String, dynamic> _polygonGeoJson() {
    final ring = [
      for (final p in _points) [p.lng, p.lat],
      if (_points.length >= 3) [_points.first.lng, _points.first.lat],
    ];
    return {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Polygon',
            'coordinates': _points.length >= 3 ? [ring] : []
          },
        },
      ],
    };
  }

  Map<String, dynamic> _pointsGeoJson() => {
        'type': 'FeatureCollection',
        'features': [
          for (final p in _points)
            {
              'type': 'Feature',
              'geometry': {
                'type': 'Point',
                'coordinates': [p.lng, p.lat]
              },
            },
        ],
      };

  Future<void> _syncMap() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null || !_styleReady) return;
    // Full-replace via setStyleSourceProperty("data", ...) rather than
    // updateGeoJSONSourceFeatures - the latter merges by feature id on web
    // (gl-js's updateData) and requires numeric ids, which is fragile for
    // a list whose length changes on every add/remove. A full replace is
    // simple and correct on both web and mobile.
    await mapboxMap.setStyleSourceProperty(
      _polygonSourceId,
      'data',
      jsonEncode(_polygonGeoJson()),
    );
    await mapboxMap.setStyleSourceProperty(
      _pointsSourceId,
      'data',
      jsonEncode(_pointsGeoJson()),
    );
  }

  Future<void> _addPointAt(Offset localPosition) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;
    final point = await mapboxMap.coordinateForPixel(
      ScreenCoordinate(x: localPosition.dx, y: localPosition.dy),
    );
    setState(() => _points.add(point.coordinates));
    await _syncMap();
  }

  Future<void> _removePoint(int index) async {
    setState(() => _points.removeAt(index));
    await _syncMap();
  }

  Future<void> _save() async {
    final resp = await NetworkManager.instance.put(
      ApiRoutes.indoorTrackingHospitalGeofence,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'geofence_polygon':
            _points.map((p) => {'lat': p.lat, 'lng': p.lng}).toList(),
        'working_hours_start': '${_startController.text}:00',
        'working_hours_end': '${_endController.text}:00',
      }),
    );
    if (resp.statusCode == 200 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Geofence & working hours saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final scheme = Theme.of(context).colorScheme;
    final noKey = const String.fromEnvironment('MAPBOX_KEY').isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hospital Geofence & Working Hours'),
        actions: [
          if (_points.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'Remove last point',
              onPressed: () => _removePoint(_points.length - 1),
            ),
          TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Save')),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                GestureDetector(
                  key: _mapKey,
                  onTapUp: (details) => _addPointAt(details.localPosition),
                  child: MapWidget(
                    viewport: CameraViewportState(
                      center: turf.Point(coordinates: _center),
                      zoom: 17,
                    ),
                    onMapCreated: _onMapCreated,
                    onStyleLoadedListener: (data) => _onStyleLoaded(),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 6)
                        ],
                      ),
                      child: Text(
                        noKey
                            ? 'MAPBOX_KEY not set (--dart-define=MAPBOX_KEY=...) — the map will fail to load tiles.'
                            : 'Tap the map to trace the hospital boundary. ${_points.length} point(s) placed.',
                        style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 320,
            child: Container(
              color: scheme.surfaceContainerLow,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'While a checked-in staff member leaves this boundary during '
                    'working hours, indoor tracking pauses and auto-resumes on '
                    'return; outside working hours, tracking stops fully.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                      controller: _startController,
                      decoration: const InputDecoration(
                          labelText: 'Working hours start (HH:MM)')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _endController,
                      decoration: const InputDecoration(
                          labelText: 'Working hours end (HH:MM)')),
                  const SizedBox(height: 20),
                  Text('Boundary points (${_points.length})',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _points.length,
                      itemBuilder: (context, i) => ListTile(
                        dense: true,
                        title: Text(
                            '${_points[i].lat.toStringAsFixed(6)}, ${_points[i].lng.toStringAsFixed(6)}',
                            style: const TextStyle(fontSize: 11)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16),
                          onPressed: () => _removePoint(i),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
