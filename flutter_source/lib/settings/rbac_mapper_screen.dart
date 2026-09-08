import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../network/api_routes.dart';
import '../network/network_manager.dart';

class _Node {
  final String id;
  final String type;
  final String label;
  Offset position;

  _Node({
    required this.id,
    required this.type,
    required this.label,
    required this.position,
  });
}

class _Edge {
  final String source;
  final String target;

  _Edge(this.source, this.target);
}

class RBACMapperScreen extends StatefulWidget {
  final bool initialRulesMode;
  const RBACMapperScreen({super.key, this.initialRulesMode = false});

  @override
  State<RBACMapperScreen> createState() => _RBACMapperScreenState();
}

class _RBACMapperScreenState extends State<RBACMapperScreen> {
  // Theme-derived colors
  Color get _bgBase => Theme.of(context).scaffoldBackgroundColor;
  Color get _surfaceContainer => Theme.of(context).colorScheme.surfaceContainer;
  Color get _surfaceContainerLow =>
      Theme.of(context).colorScheme.surfaceContainerLow;
  Color get _surfaceContainerHigh =>
      Theme.of(context).colorScheme.surfaceContainerHigh;
  Color get _tealAccent => Theme.of(context).colorScheme.secondary;
  Color get _textColor => Theme.of(context).colorScheme.onSurface;
  Color get _textVariant => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _critical => Theme.of(context).colorScheme.error;
  Color get _outlineVariant => Theme.of(context).colorScheme.outlineVariant;

  bool isLoading = true;
  bool isRulesMode = false;
  bool _isCanvasPanEnabled = true;

  // Canvas pan/zoom is InteractiveViewer. Nodes/connectors drag via raw
  // Listener (see _draggingConnector below) rather than GestureDetector's
  // onPan* — a GestureDetector there previously lost the gesture arena to
  // InteractiveViewer's own scale recognizer no matter how panEnabled was
  // toggled (flutter/flutter#28202); Listener bypasses the arena entirely,
  // so panEnabled reliably gates the one recognizer left in it.
  final TransformationController _transformationController =
      TransformationController();
  static const double _minCanvasScale = 0.4;
  static const double _maxCanvasScale = 2.5;
  double get _canvasScale =>
      _transformationController.value.getMaxScaleOnAxis();

  // A Listener never consumes/blocks pointer events the way a
  // GestureRecognizer would, so when a touch starts inside the connector's
  // hit area, BOTH the connector's own Listener and the surrounding node
  // body's Listener receive it — without this flag the node also drags at
  // the same time, which visually swamps the line-drawing effect entirely.
  bool _draggingConnector = false;

  // RBAC State
  List<_Node> rbacNodes = [];
  List<_Edge> rbacEdges = [];

  // Rules State
  List<_Node> rulesNodes = [];
  List<_Edge> rulesEdges = [];

  _Node? draggingSource;
  Offset? draggingEndPos;

  _Node? selectedNodeMenu;
  String _librarySearchQuery = '';

  bool _nodeMatchesSearch(_Node node) {
    if (_librarySearchQuery.isEmpty) return true;
    return node.label.toLowerCase().contains(_librarySearchQuery);
  }

  void _deleteNode(_Node node) async {
    setState(() => selectedNodeMenu = null);

    if (isRulesMode) {
      setState(() {
        rulesNodes.removeWhere((n) => n.id == node.id);
        rulesEdges.removeWhere(
            (e) => e.source == node.id || e.target == node.id);
      });
      _saveRulesGraph(silent: true);
      return;
    }

    if (node.type != 'group' && node.type != 'permission') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Only groups and permissions can be removed here.',
              style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.red));
      return;
    }

    final dbId = int.parse(node.id.split('_')[1]);
    final url = node.type == 'group'
        ? ApiRoutes.deleteRbacGroup(dbId)
        : ApiRoutes.deleteRbacPermission(dbId);
    try {
      await NetworkManager.instance.delete(url);
      await _fetchGraph();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error removing node: $e',
              style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.red));
    }
  }

  void _showCreateRuleNodeDialog(String type) {
    String name = "";
    final labels = {
      'entity': 'Entity',
      'condition': 'Condition',
      'zone': 'Zone',
    };
    final xByType = {'entity': 50.0, 'condition': 400.0, 'zone': 750.0};

    showDialog(
        context: context,
        builder: (ctx) => Theme(
              data: Theme.of(context).copyWith(
                  dialogTheme:
                      DialogThemeData(backgroundColor: _surfaceContainer)),
              child: AlertDialog(
                  title: Text('Add ${labels[type]}',
                      style: TextStyle(color: _textColor)),
                  content: TextField(
                    autofocus: true,
                    style: TextStyle(color: _textColor),
                    decoration: const InputDecoration(labelText: 'Name'),
                    onChanged: (v) => name = v,
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Cancel',
                            style: TextStyle(color: _textVariant))),
                    ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _tealAccent,
                            foregroundColor: _bgBase),
                        onPressed: () {
                          if (name.trim().isEmpty) return;
                          final trimmed = name.trim();
                          final id = '${type}_$trimmed';
                          if (rulesNodes.any((n) => n.id == id)) {
                            Navigator.pop(ctx);
                            return;
                          }
                          final sameTypeCount =
                              rulesNodes.where((n) => n.type == type).length;
                          setState(() {
                            rulesNodes.add(_Node(
                              id: id,
                              type: type,
                              label: trimmed,
                              position: Offset(
                                  xByType[type]!, 100 + sameTypeCount * 100),
                            ));
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text('Create')),
                  ]),
            ));
  }

  @override
  void initState() {
    super.initState();
    isRulesMode = widget.initialRulesMode;
    _fetchAll();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _fetchAll() async {
    setState(() => isLoading = true);
    await Future.wait([
      _fetchGraph(),
      _fetchRules(),
    ]);
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _fetchGraph() async {
    try {
      final resp = await NetworkManager.instance.get(ApiRoutes.rbacGraph);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final rawNodes = data['nodes'] as List<dynamic>;
        final rawEdges = data['edges'] as List<dynamic>;

        rbacNodes.clear();
        rbacEdges.clear();

        double userY = 100;
        double groupY = 100;
        double permY = 100;

        for (var n in rawNodes) {
          double x = 0;
          double y = 0;
          if (n['type'] == 'user') {
            x = 50;
            y = userY;
            userY += 100;
          } else if (n['type'] == 'group') {
            x = 400;
            y = groupY;
            groupY += 100;
          } else {
            x = 750;
            y = permY;
            permY += 100;
          }
          rbacNodes.add(_Node(
            id: n['id'],
            type: n['type'],
            label: n['label'],
            position: Offset(x, y),
          ));
        }

        for (var e in rawEdges) {
          rbacEdges.add(_Edge(e['source'], e['target']));
        }
      }
    } catch (e) {
      debugPrint("Error fetching graph: $e");
    }
  }

  Future<void> _fetchRules() async {
    rulesNodes.clear();
    rulesEdges.clear();

    final entities = ['All Staff', 'Doctors', 'Nurses', 'Patients', 'Visitors'];
    final conditions = [
      'must wear gloves',
      'must sanitize hands',
      'must wear face mask',
      'unauthorized entry prohibited'
    ];
    List<String> zones = ['ICU', 'Operating Room', 'General Ward'];
    try {
      final resp = await NetworkManager.instance.get(ApiRoutes.allUniqueRois);
      if (resp.statusCode == 200) {
        final dynamicZones =
            (jsonDecode(resp.body) as List<dynamic>).cast<String>();
        for (var z in dynamicZones) {
          if (!zones.contains(z)) {
            zones.add(z);
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching dynamic zones: $e");
    }

    double y = 100;
    for (var e in entities) {
      rulesNodes.add(_Node(
          id: 'entity_$e', type: 'entity', label: e, position: Offset(50, y)));
      y += 100;
    }

    y = 100;
    for (var c in conditions) {
      rulesNodes.add(_Node(
          id: 'condition_$c',
          type: 'condition',
          label: c,
          position: Offset(400, y)));
      y += 100;
    }

    y = 100;
    for (var z in zones) {
      rulesNodes.add(_Node(
          id: 'zone_$z', type: 'zone', label: z, position: Offset(750, y)));
      y += 100;
    }

    try {
      final resp = await NetworkManager.instance.get(ApiRoutes.securityRules);
      if (resp.statusCode == 200) {
        final rules = (jsonDecode(resp.body) as List<dynamic>)
            .cast<Map<String, dynamic>>();

        for (var r in rules) {
          final targetArea = r['target_area'];
          final ruleText = r['rule_text'] as String;

          String? matchedEntity;
          String? matchedCondition;

          for (var e in entities) {
            if (ruleText.startsWith(e)) {
              matchedEntity = e;
              matchedCondition = ruleText.substring(e.length).trim();
              break;
            }
          }

          if (matchedEntity != null && matchedCondition != null) {
            final eId = 'entity_$matchedEntity';
            final cId = 'condition_$matchedCondition';

            if (rulesNodes.any((n) => n.id == cId)) {
              if (!rulesEdges
                  .any((edge) => edge.source == eId && edge.target == cId)) {
                rulesEdges.add(_Edge(eId, cId));
              }

              if (targetArea != null) {
                final zId = 'zone_$targetArea';
                if (rulesNodes.any((n) => n.id == zId)) {
                  if (!rulesEdges.any(
                      (edge) => edge.source == cId && edge.target == zId)) {
                    rulesEdges.add(_Edge(cId, zId));
                  }
                }
              }
            }
          }
        }
      }
    } catch (_) {}
  }

  void _handleDrop(_Node source, Offset dropPos) async {
    final activeNodes = isRulesMode ? rulesNodes : rbacNodes;
    final activeEdges = isRulesMode ? rulesEdges : rbacEdges;

    _Node? targetNode;
    for (var n in activeNodes) {
      if (n.id == source.id) continue;
      final rect =
          Rect.fromLTWH(n.position.dx - 40, n.position.dy - 20, 320, 100);
      if (rect.contains(dropPos)) {
        targetNode = n;
        break;
      }
    }

    if (targetNode != null) {
      String sourceId = source.id;
      String targetId = targetNode.id;

      if (isRulesMode) {
        final srcType = source.type;
        final tgtType = targetNode.type;

        if (srcType == 'condition' && tgtType == 'entity') {
          sourceId = targetNode.id;
          targetId = source.id;
        } else if (srcType == 'zone' && tgtType == 'condition') {
          sourceId = targetNode.id;
          targetId = source.id;
        } else if ((srcType == 'entity' && tgtType == 'condition') ||
            (srcType == 'condition' && tgtType == 'zone')) {
          // Valid
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Invalid connection. Entities -> Conditions -> Zones.',
                  style: TextStyle(color: Colors.white)),
              backgroundColor: Colors.red));
          setState(() {
            draggingSource = null;
            draggingEndPos = null;
          });
          return;
        }
      } else {
        final srcType = source.type;
        final tgtType = targetNode.type;
        if ((tgtType == 'user' && srcType == 'group') ||
            (tgtType == 'group' && srcType == 'permission')) {
          sourceId = targetNode.id;
          targetId = source.id;
        }
      }

      final existingEdgeIdx = activeEdges.indexWhere((e) =>
          (e.source == sourceId && e.target == targetId) ||
          (e.source == targetId && e.target == sourceId));

      if (existingEdgeIdx == -1) {
        setState(() => activeEdges.add(_Edge(sourceId, targetId)));

        if (!isRulesMode) {
          final srcType = sourceId.split('_')[0];
          final srcDbId = int.parse(sourceId.split('_')[1]);
          final tgtType = targetId.split('_')[0];
          final tgtDbId = int.parse(targetId.split('_')[1]);

          await NetworkManager.instance.post(ApiRoutes.rbacAssign,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                "source_type": srcType,
                "source_id": srcDbId,
                "target_type": tgtType,
                "target_id": tgtDbId
              }));
        } else {
          _saveRulesGraph(silent: true);
        }
      }
    }
    setState(() {
      draggingSource = null;
      draggingEndPos = null;
    });
  }

  void _deleteEdge(_Edge edge) async {
    if (isRulesMode) {
      setState(() => rulesEdges.remove(edge));
      _saveRulesGraph(silent: true);
    } else {
      setState(() => rbacEdges.remove(edge));
      final srcType = edge.source.split('_')[0];
      final srcDbId = int.parse(edge.source.split('_')[1]);
      final tgtType = edge.target.split('_')[0];
      final tgtDbId = int.parse(edge.target.split('_')[1]);

      await NetworkManager.instance.post(ApiRoutes.rbacUnassign,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            "source_type": srcType,
            "source_id": srcDbId,
            "target_type": tgtType,
            "target_id": tgtDbId
          }));
    }
  }

  Future<void> _saveRulesGraph({bool silent = false}) async {
    if (!silent) setState(() => isLoading = true);

    List<Map<String, dynamic>> compiledRules = [];

    for (var entityNode in rulesNodes.where((n) => n.type == 'entity')) {
      final connectedConditions = rulesEdges
          .where((e) => e.source == entityNode.id)
          .map((e) => e.target)
          .toList();
      for (var cId in connectedConditions) {
        final conditionNode = rulesNodes.firstWhere((n) => n.id == cId);

        final connectedZones = rulesEdges
            .where((e) => e.source == cId)
            .map((e) => e.target)
            .toList();

        if (connectedZones.isEmpty) {
          compiledRules.add({
            "target_area": null,
            "rule_text": "${entityNode.label} ${conditionNode.label}"
          });
        } else {
          for (var zId in connectedZones) {
            final zoneNode = rulesNodes.firstWhere((n) => n.id == zId);

            compiledRules.add({
              "target_area": zoneNode.label,
              "rule_text": "${entityNode.label} ${conditionNode.label}"
            });
          }
        }
      }
    }

    try {
      await NetworkManager.instance.post(
        ApiRoutes.securityRulesSync,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"rules": compiledRules}),
      );
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('AI Rules synchronized successfully!',
                style: TextStyle(color: _bgBase, fontWeight: FontWeight.bold)),
            backgroundColor: _tealAccent));
      }
    } catch (e) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error saving rules: $e',
                style: TextStyle(color: _textColor)),
            backgroundColor: Colors.red));
      }
    }
    if (!silent) setState(() => isLoading = false);
  }

  void _showCreateNodeDialog(String type) {
    String name = "";
    String desc = "";

    showDialog(
        context: context,
        builder: (ctx) => Theme(
              data: Theme.of(context).copyWith(
                  dialogTheme:
                      DialogThemeData(backgroundColor: _surfaceContainer)),
              child: AlertDialog(
                  title: Text(
                      type == 'group'
                          ? 'Create Custom Group'
                          : 'Create Custom Permission',
                      style: TextStyle(color: _textColor)),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                      style: TextStyle(color: _textColor),
                      decoration: const InputDecoration(labelText: 'Name'),
                      onChanged: (v) => name = v,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      style: TextStyle(color: _textColor),
                      decoration:
                          const InputDecoration(labelText: 'Description'),
                      onChanged: (v) => desc = v,
                    ),
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Cancel',
                            style: TextStyle(color: _textVariant))),
                    ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _tealAccent,
                            foregroundColor: _bgBase),
                        onPressed: () async {
                          if (name.trim().isEmpty) return;
                          Navigator.pop(ctx);
                          setState(() => isLoading = true);

                          final url = type == 'group'
                              ? ApiRoutes.rbacGroups
                              : ApiRoutes.rbacPermissions;
                          try {
                            await NetworkManager.instance.post(url,
                                headers: {'Content-Type': 'application/json'},
                                body: jsonEncode({
                                  "name": name.trim(),
                                  "description": desc.trim()
                                }));
                            await _fetchGraph();
                          } catch (_) {}
                          if (mounted) setState(() => isLoading = false);
                        },
                        child: const Text('Create'))
                  ]),
            ));
  }

  @override
  Widget build(BuildContext context) {
    final activeNodes = isRulesMode ? rulesNodes : rbacNodes;
    final activeEdges = isRulesMode ? rulesEdges : rbacEdges;

    return Scaffold(
      backgroundColor: _bgBase,
      appBar: AppBar(
        // Reached via context.go(), which replaces the whole route stack —
        // there's nothing for the default back button to pop to.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/settings'),
        ),
        title: Row(
          children: [
            Text('Access Node Mapper',
                style:
                    TextStyle(fontWeight: FontWeight.bold, color: _textColor)),
            const SizedBox(width: 24),
            Container(
              decoration: BoxDecoration(
                color: _surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _outlineVariant),
              ),
              child: ToggleButtons(
                isSelected: [!isRulesMode, isRulesMode],
                onPressed: (index) {
                  setState(() {
                    isRulesMode = index == 1;
                    selectedNodeMenu = null;
                  });
                },
                borderRadius: BorderRadius.circular(8),
                borderColor: Colors.transparent,
                selectedBorderColor: Colors.transparent,
                color: _textVariant,
                selectedColor: _bgBase,
                fillColor: _tealAccent,
                constraints: const BoxConstraints(minHeight: 36, minWidth: 140),
                children: const [
                  Text('Access Protocols',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text('AI Security Rules',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            )
          ],
        ),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: _textColor),
        elevation: 0,
        actions: [
          if (isRulesMode)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
              child: ElevatedButton.icon(
                onPressed: _saveRulesGraph,
                icon: const Icon(Icons.bolt, size: 18),
                label: const Text('Deploy Protocol',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _tealAccent,
                    foregroundColor: _bgBase,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
              ),
            ),
          IconButton(
              icon: Icon(Icons.refresh, color: _textColor),
              onPressed: _fetchAll),
          const SizedBox(width: 16),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: _tealAccent))
          : Row(
              children: [
                // Canvas Area
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // The canvas must stay at least as large as the visible
                      // viewport even at the most-zoomed-out scale — otherwise
                      // zooming out reveals a blank strip past the canvas edge
                      // where the grid stops.
                      final canvasWidth =
                          (constraints.maxWidth / _minCanvasScale)
                              .clamp(4000.0, double.infinity);
                      final canvasHeight =
                          (constraints.maxHeight / _minCanvasScale)
                              .clamp(6000.0, double.infinity);
                      // Nodes and the connector drag exclusively via raw
                      // Listener (see _draggingConnector above), which never
                      // enters Flutter's gesture arena — so InteractiveViewer
                      // no longer has any competing recognizer to fight over
                      // a touch, and panEnabled reliably gates the ONE
                      // recognizer that's actually in the arena. This also
                      // restores real two-finger pinch-to-zoom for free,
                      // which the hand-rolled scroll-wheel-only version
                      // didn't have.
                      return InteractiveViewer(
                        transformationController: _transformationController,
                        constrained: false,
                        panEnabled: _isCanvasPanEnabled,
                        minScale: _minCanvasScale,
                        maxScale: _maxCanvasScale,
                        boundaryMargin: const EdgeInsets.all(400),
                        child: GestureDetector(
                          onTap: () {
                            if (selectedNodeMenu != null) {
                              setState(() => selectedNodeMenu = null);
                            }
                          },
                          child: SizedBox(
                            width: canvasWidth,
                            height: canvasHeight,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                // Background pattern/connectors placeholder
                                Positioned.fill(
                                  child: Opacity(
                                    opacity: 0.1,
                                    child: CustomPaint(
                                      painter: _BackgroundGridPainter(
                                          lineColor: _outlineVariant),
                                    ),
                                  ),
                                ),
                                // Column Titles
                                Positioned(
                                    left: 50,
                                    top: 20,
                                    child: Text(
                                        isRulesMode
                                            ? 'ENTITIES'
                                            : 'SOURCE NODES',
                                        style: TextStyle(
                                            color: _tealAccent,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.5))),
                                Positioned(
                                    left: 400,
                                    top: 20,
                                    child: Text(
                                        isRulesMode
                                            ? 'CONDITIONS'
                                            : 'GROUPS / ZONES',
                                        style: TextStyle(
                                            color: _tealAccent,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.5))),
                                Positioned(
                                    left: 750,
                                    top: 20,
                                    child: Text(
                                        isRulesMode
                                            ? 'TARGET ZONES'
                                            : 'PERMISSION LEVELS',
                                        style: TextStyle(
                                            color: _tealAccent,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.5))),

                                // Edges
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _EdgePainter(
                                        activeNodes,
                                        activeEdges,
                                        draggingSource,
                                        draggingEndPos,
                                        isRulesMode,
                                        _tealAccent),
                                  ),
                                ),
                                // Edge Delete Buttons
                                ...activeEdges.map((e) {
                                  final sourceNode = activeNodes
                                      .cast<_Node?>()
                                      .firstWhere((n) => n?.id == e.source,
                                          orElse: () => null);
                                  final targetNode = activeNodes
                                      .cast<_Node?>()
                                      .firstWhere((n) => n?.id == e.target,
                                          orElse: () => null);
                                  if (sourceNode == null || targetNode == null)
                                    return const SizedBox.shrink();

                                  final midX = sourceNode.position.dx +
                                      220 +
                                      (targetNode.position.dx -
                                              (sourceNode.position.dx + 220)) /
                                          2;
                                  final midY = sourceNode.position.dy +
                                      35 +
                                      (targetNode.position.dy -
                                              sourceNode.position.dy) /
                                          2;

                                  return Positioned(
                                      left: midX - 12,
                                      top: midY - 12,
                                      child: InkWell(
                                          onTap: () => _deleteEdge(e),
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                                color: _surfaceContainerHigh,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                    color: _outlineVariant)),
                                            child: Icon(Icons.close,
                                                size: 14, color: _textColor),
                                          )));
                                }),
                                // Nodes
                                ...activeNodes
                                    .where(_nodeMatchesSearch)
                                    .map((node) {
                                  Color nodeColor;
                                  IconData icon;
                                  Color bgContainer = _surfaceContainer;
                                  if (node.type == 'user' ||
                                      node.type == 'entity') {
                                    nodeColor = _tealAccent;
                                    icon = Icons.person;
                                  } else if (node.type == 'group' ||
                                      node.type == 'condition') {
                                    nodeColor = Colors.orangeAccent;
                                    icon = Icons.hub;
                                  } else if (node.type == 'zone') {
                                    nodeColor = Colors.redAccent;
                                    icon = Icons.emergency;
                                  } else if (node.type == 'permission') {
                                    nodeColor = Colors.greenAccent;
                                    icon = Icons.vpn_key;
                                  } else {
                                    nodeColor = _textVariant;
                                    icon = Icons.device_unknown;
                                  }

                                  bool isSelected = selectedNodeMenu == node;

                                  return Positioned(
                                    left: node.position.dx,
                                    top: node.position.dy,
                                    // Node dragging uses raw Listener pointer
                                    // events rather than GestureDetector's
                                    // onPan* callbacks: nested inside an
                                    // InteractiveViewer, a PanGestureRecognizer
                                    // reliably loses the gesture arena to
                                    // InteractiveViewer's own ScaleGesture
                                    // recognizer, so onPanUpdate never fires
                                    // and the canvas pans instead. Listener
                                    // receives pointer events unconditionally,
                                    // bypassing the arena entirely.
                                    child: Listener(
                                      onPointerDown: (_) {
                                        // The connector's own Listener
                                        // (nested below) already claimed
                                        // this touch — don't also start
                                        // dragging the node.
                                        if (_draggingConnector || !mounted) {
                                          return;
                                        }
                                        setState(
                                            () => _isCanvasPanEnabled = false);
                                      },
                                      onPointerMove: (event) {
                                        if (_draggingConnector || !mounted) {
                                          return;
                                        }
                                        setState(() {
                                          // event.delta is in screen pixels;
                                          // the canvas content is drawn at
                                          // _canvasScale, so divide to get the
                                          // equivalent movement in canvas
                                          // (model) coordinates.
                                          node.position +=
                                              event.delta / _canvasScale;
                                          if (selectedNodeMenu != null) {
                                            selectedNodeMenu = null;
                                          }
                                        });
                                      },
                                      // Raw pointer callbacks (unlike
                                      // GestureDetector recognizers) aren't
                                      // automatically cancelled when a widget
                                      // is disposed mid-drag — e.g. navigating
                                      // away from this screen while a finger
                                      // is still down — so every handler here
                                      // guards with `mounted` to avoid
                                      // "setState() called after dispose()".
                                      onPointerUp: (_) {
                                        if (!mounted) return;
                                        setState(
                                            () => _isCanvasPanEnabled = true);
                                      },
                                      onPointerCancel: (_) {
                                        if (!mounted) return;
                                        setState(
                                            () => _isCanvasPanEnabled = true);
                                      },
                                      child: GestureDetector(
                                        onTap: () => setState(() =>
                                            selectedNodeMenu =
                                                isSelected ? null : node),
                                        // Widened from 240 to 264 so the
                                        // connector's 44x44 hit target
                                        // (below, positioned via `left`,
                                        // centered on the body's real
                                        // right edge at x=240) is fully
                                        // inside this box. A RenderBox
                                        // rejects hit-tests outside its
                                        // own reported size before ever
                                        // considering overflowing
                                        // children, so the enlarged
                                        // connector target was mostly
                                        // unreachable when this box
                                        // stopped at 240.
                                        child: SizedBox(
                                          width: 264,
                                          height: 70,
                                          child: Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              Positioned(
                                                left: 0,
                                                top: 0,
                                                width: 240,
                                                height: 70,
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: isSelected
                                                        ? _surfaceContainerHigh
                                                        : bgContainer,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                    border: Border.all(
                                                        color: isSelected
                                                            ? _tealAccent
                                                            : _outlineVariant,
                                                        width:
                                                            isSelected ? 2 : 1),
                                                    boxShadow: [
                                                      if (isSelected)
                                                        BoxShadow(
                                                            color: _tealAccent
                                                                .withValues(
                                                                    alpha: 0.2),
                                                            blurRadius: 12,
                                                            spreadRadius: 2)
                                                    ],
                                                  ),
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 16,
                                                      vertical: 12),
                                                  child: Row(
                                                    children: [
                                                      Container(
                                                        width: 40,
                                                        height: 40,
                                                        decoration:
                                                            BoxDecoration(
                                                          color: nodeColor
                                                              .withValues(
                                                                  alpha: 0.1),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                        ),
                                                        child: Icon(icon,
                                                            color: nodeColor,
                                                            size: 20),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            Text(node.label,
                                                                style: TextStyle(
                                                                    color:
                                                                        _textColor,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    fontSize:
                                                                        13),
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis),
                                                            Text(
                                                                node.type
                                                                    .toUpperCase(),
                                                                style: TextStyle(
                                                                    color:
                                                                        _textVariant,
                                                                    fontSize: 9,
                                                                    letterSpacing:
                                                                        0.5)),
                                                          ],
                                                        ),
                                                      )
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              // Connection Port (visual dot is
                                              // 16x16, but the drag/tap target is
                                              // enlarged to 44x44 — a touch target
                                              // that small was getting missed and
                                              // falling through to the canvas pan
                                              // gesture).
                                              Positioned(
                                                // Anchored via `left` to
                                                // the body's fixed right
                                                // edge (x=240) rather than
                                                // `right` (relative to
                                                // this now-wider 264
                                                // Stack) so the dot's
                                                // visual center stays at
                                                // exactly (240, 35) as
                                                // before.
                                                left: 240 - 8 - 14,
                                                top: 27 - 14,
                                                // Same Listener-based approach as
                                                // the node body drag above — a
                                                // GestureDetector here reliably
                                                // lost the arena to
                                                // InteractiveViewer's own scale
                                                // recognizer, so the connector
                                                // never fired onPanUpdate and the
                                                // canvas panned instead.
                                                child: Listener(
                                                  onPointerDown: (_) {
                                                    if (!mounted) return;
                                                    setState(() {
                                                      // Claimed first so
                                                      // the enclosing node
                                                      // body's Listener
                                                      // (which also sees
                                                      // this same touch)
                                                      // stands down.
                                                      _draggingConnector = true;
                                                      _isCanvasPanEnabled =
                                                          false;
                                                      draggingSource = node;
                                                      draggingEndPos = node
                                                              .position +
                                                          const Offset(240, 35);
                                                    });
                                                  },
                                                  onPointerMove: (event) {
                                                    if (!mounted) return;
                                                    setState(() {
                                                      draggingEndPos =
                                                          draggingEndPos! +
                                                              event.delta /
                                                                  _canvasScale;
                                                    });
                                                  },
                                                  // See the node-level
                                                  // Listener's comment above:
                                                  // raw pointer callbacks
                                                  // aren't auto-cancelled on
                                                  // dispose, so guard every
                                                  // handler with `mounted`.
                                                  onPointerUp: (_) {
                                                    if (!mounted) return;
                                                    setState(() {
                                                      _draggingConnector =
                                                          false;
                                                      _isCanvasPanEnabled =
                                                          true;
                                                    });
                                                    _handleDrop(
                                                        node, draggingEndPos!);
                                                  },
                                                  onPointerCancel: (_) {
                                                    if (!mounted) return;
                                                    setState(() {
                                                      _draggingConnector =
                                                          false;
                                                      _isCanvasPanEnabled =
                                                          true;
                                                    });
                                                  },
                                                  child: SizedBox(
                                                    width: 44,
                                                    height: 44,
                                                    child: Center(
                                                      child: Container(
                                                        width: 16,
                                                        height: 16,
                                                        decoration: BoxDecoration(
                                                            color: _bgBase,
                                                            shape:
                                                                BoxShape.circle,
                                                            border: Border.all(
                                                                color:
                                                                    _outlineVariant,
                                                                width: 2)),
                                                        child: Center(
                                                          child: Container(
                                                            width: 6,
                                                            height: 6,
                                                            decoration: BoxDecoration(
                                                                color: _tealAccent
                                                                    .withValues(
                                                                        alpha:
                                                                            0.8),
                                                                shape: BoxShape
                                                                    .circle),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              )
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),

                                // Floating Context Menu
                                if (selectedNodeMenu != null)
                                  Positioned(
                                    left: selectedNodeMenu!.position.dx + 20,
                                    top: selectedNodeMenu!.position.dy + 80,
                                    child: Material(
                                      color: Colors.transparent,
                                      elevation: 8,
                                      borderRadius: BorderRadius.circular(12),
                                      child: Container(
                                        width: 220,
                                        decoration: BoxDecoration(
                                          color: _surfaceContainerHigh,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: _outlineVariant),
                                        ),
                                        child: Material(
                                          type: MaterialType.transparency,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              ListTile(
                                                leading: Icon(
                                                    Icons.info_outline,
                                                    color: _textVariant,
                                                    size: 20),
                                                title: Text('Node details',
                                                    style: TextStyle(
                                                        color: _textColor,
                                                        fontSize: 13)),
                                                onTap: () => setState(() =>
                                                    selectedNodeMenu = null),
                                              ),
                                              Divider(
                                                  height: 1,
                                                  color: _outlineVariant),
                                              ListTile(
                                                leading: Icon(
                                                    Icons.delete_outline,
                                                    color: _critical,
                                                    size: 20),
                                                title: Text('Remove node',
                                                    style: TextStyle(
                                                        color: _critical,
                                                        fontSize: 13)),
                                                onTap: () =>
                                                    _deleteNode(selectedNodeMenu!),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Right Sidebar Library
                Container(
                  width: 280,
                  decoration: BoxDecoration(
                    color: _surfaceContainerLow,
                    border: Border(left: BorderSide(color: _outlineVariant)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: TextField(
                          style: TextStyle(color: _textColor, fontSize: 14),
                          onChanged: (v) => setState(
                              () => _librarySearchQuery = v.trim().toLowerCase()),
                          decoration: InputDecoration(
                            hintText: 'Search items...',
                            hintStyle: TextStyle(color: _textVariant),
                            prefixIcon: Icon(Icons.search,
                                color: _textVariant, size: 20),
                            filled: true,
                            fillColor: _surfaceContainer,
                            border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(8)),
                                borderSide: BorderSide(color: _outlineVariant)),
                            enabledBorder: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(8)),
                                borderSide: BorderSide(color: _outlineVariant)),
                            contentPadding: EdgeInsets.symmetric(vertical: 0),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          children: [
                            Text('LIBRARY',
                                style: TextStyle(
                                    color: _textVariant,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1)),
                            const SizedBox(height: 16),
                            if (!isRulesMode) ...[
                              _SidebarItem(
                                  icon: Icons.group_add,
                                  label: 'Create Group',
                                  onTap: () => _showCreateNodeDialog('group')),
                              const SizedBox(height: 12),
                              _SidebarItem(
                                  icon: Icons.security,
                                  label: 'Create Permission',
                                  onTap: () =>
                                      _showCreateNodeDialog('permission')),
                            ] else ...[
                              _SidebarItem(
                                  icon: Icons.people,
                                  label: 'Add Entity',
                                  onTap: () =>
                                      _showCreateRuleNodeDialog('entity')),
                              const SizedBox(height: 12),
                              _SidebarItem(
                                  icon: Icons.rule,
                                  label: 'Add Condition',
                                  onTap: () =>
                                      _showCreateRuleNodeDialog('condition')),
                              const SizedBox(height: 12),
                              _SidebarItem(
                                  icon: Icons.location_on,
                                  label: 'Add Zone',
                                  onTap: () =>
                                      _showCreateRuleNodeDialog('zone')),
                            ]
                          ],
                        ),
                      )
                    ],
                  ),
                )
              ],
            ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SidebarItem(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outlineVariant)),
        child: Row(
          children: [
            Icon(icon, color: scheme.secondary, size: 18),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _BackgroundGridPainter extends CustomPainter {
  final Color lineColor;
  _BackgroundGridPainter({required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.0;

    for (double i = 0; i < size.width; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double j = 0; j < size.height; j += 40) {
      canvas.drawLine(Offset(0, j), Offset(size.width, j), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EdgePainter extends CustomPainter {
  final List<_Node> nodes;
  final List<_Edge> edges;
  final _Node? draggingSource;
  final Offset? draggingEndPos;
  final bool isRulesMode;
  final Color accentColor;

  _EdgePainter(this.nodes, this.edges, this.draggingSource, this.draggingEndPos,
      this.isRulesMode, this.accentColor);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accentColor.withValues(alpha: 0.6)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    for (var edge in edges) {
      final sourceNode = nodes
          .cast<_Node?>()
          .firstWhere((n) => n?.id == edge.source, orElse: () => null);
      final targetNode = nodes
          .cast<_Node?>()
          .firstWhere((n) => n?.id == edge.target, orElse: () => null);

      if (sourceNode != null && targetNode != null) {
        final start =
            Offset(sourceNode.position.dx + 240, sourceNode.position.dy + 35);
        final end = Offset(targetNode.position.dx, targetNode.position.dy + 35);

        final path = Path();
        path.moveTo(start.dx, start.dy);
        final controlPoint1 =
            Offset(start.dx + (end.dx - start.dx) / 2, start.dy);
        final controlPoint2 =
            Offset(start.dx + (end.dx - start.dx) / 2, end.dy);
        path.cubicTo(controlPoint1.dx, controlPoint1.dy, controlPoint2.dx,
            controlPoint2.dy, end.dx, end.dy);
        canvas.drawPath(path, paint);

        // Draw connection dot
        canvas.drawCircle(
            start,
            4,
            Paint()
              ..color = accentColor
              ..style = PaintingStyle.fill);
        canvas.drawCircle(
            end,
            4,
            Paint()
              ..color = accentColor
              ..style = PaintingStyle.fill);
      }
    }

    if (draggingSource != null && draggingEndPos != null) {
      final start = Offset(
          draggingSource!.position.dx + 240, draggingSource!.position.dy + 35);
      final end = draggingEndPos!;

      final dragPaint = Paint()
        ..color = accentColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;

      final path = Path();
      path.moveTo(start.dx, start.dy);
      final controlPoint1 =
          Offset(start.dx + (end.dx - start.dx) / 2, start.dy);
      final controlPoint2 = Offset(start.dx + (end.dx - start.dx) / 2, end.dy);
      path.cubicTo(controlPoint1.dx, controlPoint1.dy, controlPoint2.dx,
          controlPoint2.dy, end.dx, end.dy);
      canvas.drawPath(path, dragPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
