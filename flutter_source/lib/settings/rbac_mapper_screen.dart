import 'dart:convert';

import 'package:flutter/material.dart';

import '../network/api_routes.dart';
import '../network/network_manager.dart';

const Color _bgBase = Color(0xFF041329);
const Color _surfaceContainer = Color(0xFF112036);
const Color _surfaceContainerLow = Color(0xFF0d1c32);
const Color _surfaceContainerHigh = Color(0xFF1c2a41);
const Color _tealAccent = Color(0xFF38debb);
const Color _textColor = Color(0xFFd6e3ff);
const Color _textVariant = Color(0xFFbacac3);
const Color _critical = Color(0xFFffb4ab);
const Color _outlineVariant = Color(0xFF3c4a45);

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
  bool isLoading = true;
  bool isRulesMode = false;
  bool _isCanvasPanEnabled = true;

  // RBAC State
  List<_Node> rbacNodes = [];
  List<_Edge> rbacEdges = [];

  // Rules State
  List<_Node> rulesNodes = [];
  List<_Edge> rulesEdges = [];

  _Node? draggingSource;
  Offset? draggingEndPos;

  _Node? selectedNodeMenu;

  @override
  void initState() {
    super.initState();
    isRulesMode = widget.initialRulesMode;
    _fetchAll();
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
        final dynamicZones = (jsonDecode(resp.body) as List<dynamic>).cast<String>();
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
      final rect = Rect.fromLTWH(n.position.dx - 40, n.position.dy - 20, 320, 100);
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
              content: Text('Invalid connection. Entities -> Conditions -> Zones.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red));
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('AI Rules synchronized successfully!', style: TextStyle(color: _bgBase, fontWeight: FontWeight.bold)),
            backgroundColor: _tealAccent));
      }
    } catch (e) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error saving rules: $e', style: const TextStyle(color: Colors.white)),
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
              data: ThemeData.dark().copyWith(dialogTheme: DialogThemeData(backgroundColor: _surfaceContainer)),
              child: AlertDialog(
                  title: Text(type == 'group' ? 'Create Custom Group' : 'Create Custom Permission', style: const TextStyle(color: Colors.white)),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Name'),
                      onChanged: (v) => name = v,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Description'),
                      onChanged: (v) => desc = v,
                    ),
                  ]),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: _textVariant))),
                    ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: _tealAccent, foregroundColor: _bgBase),
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
        title: Row(
          children: [
            const Text('Access Node Mapper', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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
                  Text('Access Protocols', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Text('AI Security Rules', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            )
          ],
        ),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          if (isRulesMode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
              child: ElevatedButton.icon(
                onPressed: _saveRulesGraph,
                icon: const Icon(Icons.bolt, size: 18),
                label: const Text('Deploy Protocol', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: _tealAccent,
                    foregroundColor: _bgBase,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              ),
            ),
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _fetchAll),
          const SizedBox(width: 16),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: _tealAccent))
          : Row(
              children: [
                // Canvas Area
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (selectedNodeMenu != null) {
                        setState(() => selectedNodeMenu = null);
                      }
                    },
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        // Background pattern/connectors placeholder
                        Positioned.fill(
                          child: Opacity(
                            opacity: 0.1,
                            child: CustomPaint(
                              painter: _BackgroundGridPainter(),
                            ),
                          ),
                        ),
                        // Column Titles
                        Positioned(left: 50, top: 20, child: Text(isRulesMode ? 'ENTITIES' : 'SOURCE NODES', style: const TextStyle(color: _tealAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5))),
                        Positioned(left: 400, top: 20, child: Text(isRulesMode ? 'CONDITIONS' : 'GROUPS / ZONES', style: const TextStyle(color: _tealAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5))),
                        Positioned(left: 750, top: 20, child: Text(isRulesMode ? 'TARGET ZONES' : 'PERMISSION LEVELS', style: const TextStyle(color: _tealAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5))),

                        // Edges
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _EdgePainter(activeNodes, activeEdges, draggingSource, draggingEndPos, isRulesMode),
                          ),
                        ),
                        // Edge Delete Buttons
                        ...activeEdges.map((e) {
                          final sourceNode = activeNodes.cast<_Node?>().firstWhere((n) => n?.id == e.source, orElse: () => null);
                          final targetNode = activeNodes.cast<_Node?>().firstWhere((n) => n?.id == e.target, orElse: () => null);
                          if (sourceNode == null || targetNode == null) return const SizedBox.shrink();

                          final midX = sourceNode.position.dx + 220 + (targetNode.position.dx - (sourceNode.position.dx + 220)) / 2;
                          final midY = sourceNode.position.dy + 35 + (targetNode.position.dy - sourceNode.position.dy) / 2;

                          return Positioned(
                              left: midX - 12,
                              top: midY - 12,
                              child: InkWell(
                                  onTap: () => _deleteEdge(e),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(color: _surfaceContainerHigh, shape: BoxShape.circle, border: Border.all(color: _outlineVariant)),
                                    child: const Icon(Icons.close, size: 14, color: _textColor),
                                  )));
                        }),
                        // Nodes
                        ...activeNodes.map((node) {
                          Color nodeColor;
                          IconData icon;
                          Color bgContainer = _surfaceContainer;
                          if (node.type == 'user' || node.type == 'entity') {
                            nodeColor = _tealAccent;
                            icon = Icons.person;
                          } else if (node.type == 'group' || node.type == 'condition') {
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
                            child: GestureDetector(
                              onTap: () => setState(() => selectedNodeMenu = isSelected ? null : node),
                              onPanDown: (_) => setState(() => _isCanvasPanEnabled = false),
                              onPanCancel: () => setState(() => _isCanvasPanEnabled = true),
                              onPanEnd: (_) => setState(() => _isCanvasPanEnabled = true),
                              onPanUpdate: (details) {
                                setState(() => node.position += details.delta);
                                if (selectedNodeMenu != null) selectedNodeMenu = null;
                              },
                              child: SizedBox(
                                width: 240,
                                height: 70,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        color: isSelected ? _surfaceContainerHigh : bgContainer,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: isSelected ? _tealAccent : _outlineVariant, width: isSelected ? 2 : 1),
                                        boxShadow: [
                                          if (isSelected) BoxShadow(color: _tealAccent.withValues(alpha: 0.2), blurRadius: 12, spreadRadius: 2)
                                        ],
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: nodeColor.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Icon(icon, color: nodeColor, size: 20),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(node.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                Text(node.type.toUpperCase(), style: const TextStyle(color: _textVariant, fontSize: 9, letterSpacing: 0.5)),
                                              ],
                                            ),
                                          )
                                        ],
                                      ),
                                    ),
                                    // Connection Port
                                    Positioned(
                                      right: -8,
                                      top: 27,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.translucent,
                                        onPanDown: (_) => setState(() => _isCanvasPanEnabled = false),
                                        onPanCancel: () => setState(() => _isCanvasPanEnabled = true),
                                        onPanStart: (d) => setState(() {
                                          draggingSource = node;
                                          draggingEndPos = node.position + const Offset(240, 35);
                                        }),
                                        onPanUpdate: (d) => setState(() {
                                          draggingEndPos = draggingEndPos! + d.delta;
                                        }),
                                        onPanEnd: (d) {
                                          setState(() => _isCanvasPanEnabled = true);
                                          _handleDrop(node, draggingEndPos!);
                                        },
                                        child: Container(
                                          width: 16,
                                          height: 16,
                                          decoration: BoxDecoration(color: _bgBase, shape: BoxShape.circle, border: Border.all(color: _outlineVariant, width: 2)),
                                          child: Center(
                                            child: Container(
                                              width: 6,
                                              height: 6,
                                              decoration: BoxDecoration(color: _tealAccent.withValues(alpha: 0.8), shape: BoxShape.circle),
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
                        }),

                        // Floating Context Menu
                        if (selectedNodeMenu != null)
                          Positioned(
                            left: selectedNodeMenu!.position.dx + 20,
                            top: selectedNodeMenu!.position.dy + 80,
                            child: Material(
                              color: Colors.transparent,
                              elevation: 8,
                              child: Container(
                                width: 220,
                                decoration: BoxDecoration(
                                  color: _surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: _outlineVariant),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ListTile(
                                      leading: const Icon(Icons.info_outline, color: _textVariant, size: 20),
                                      title: const Text('Node details', style: TextStyle(color: Colors.white, fontSize: 13)),
                                      onTap: () => setState(() => selectedNodeMenu = null),
                                    ),
                                    const Divider(height: 1, color: _outlineVariant),
                                    ListTile(
                                      leading: const Icon(Icons.delete_outline, color: _critical, size: 20),
                                      title: const Text('Remove node', style: TextStyle(color: _critical, fontSize: 13)),
                                      onTap: () {
                                        setState(() => selectedNodeMenu = null);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                      ],
                    ),
                  ),
                ),

                // Right Sidebar Library
                Container(
                  width: 280,
                  decoration: const BoxDecoration(
                    color: _surfaceContainerLow,
                    border: Border(left: BorderSide(color: _outlineVariant)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(24.0),
                        child: TextField(
                          style: TextStyle(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Search items...',
                            hintStyle: TextStyle(color: _textVariant),
                            prefixIcon: Icon(Icons.search, color: _textVariant, size: 20),
                            filled: true,
                            fillColor: _surfaceContainer,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.all(Radius.circular(8)),
                                borderSide: BorderSide(color: _outlineVariant)),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.all(Radius.circular(8)),
                                borderSide: BorderSide(color: _outlineVariant)),
                            contentPadding: EdgeInsets.symmetric(vertical: 0),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          children: [
                            const Text('LIBRARY', style: TextStyle(color: _textVariant, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                            const SizedBox(height: 16),
                            if (!isRulesMode) ...[
                              _SidebarItem(icon: Icons.group_add, label: 'Create Group', onTap: () => _showCreateNodeDialog('group')),
                              const SizedBox(height: 12),
                              _SidebarItem(icon: Icons.security, label: 'Create Permission', onTap: () => _showCreateNodeDialog('permission')),
                            ] else ...[
                              _SidebarItem(icon: Icons.people, label: 'Add Entity', onTap: () {}),
                              const SizedBox(height: 12),
                              _SidebarItem(icon: Icons.rule, label: 'Add Condition', onTap: () {}),
                              const SizedBox(height: 12),
                              _SidebarItem(icon: Icons.location_on, label: 'Add Zone', onTap: () {}),
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

  const _SidebarItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
            color: _surfaceContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _outlineVariant)),
        child: Row(
          children: [
            Icon(icon, color: _tealAccent, size: 18),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _BackgroundGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _outlineVariant
      ..strokeWidth = 1.0;

    for(double i = 0; i < size.width; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for(double j = 0; j < size.height; j += 40) {
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

  _EdgePainter(this.nodes, this.edges, this.draggingSource, this.draggingEndPos, this.isRulesMode);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _tealAccent.withValues(alpha: 0.6)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    for (var edge in edges) {
      final sourceNode = nodes.cast<_Node?>().firstWhere((n) => n?.id == edge.source, orElse: () => null);
      final targetNode = nodes.cast<_Node?>().firstWhere((n) => n?.id == edge.target, orElse: () => null);

      if (sourceNode != null && targetNode != null) {
        final start = Offset(sourceNode.position.dx + 240, sourceNode.position.dy + 35);
        final end = Offset(targetNode.position.dx, targetNode.position.dy + 35);

        final path = Path();
        path.moveTo(start.dx, start.dy);
        final controlPoint1 = Offset(start.dx + (end.dx - start.dx) / 2, start.dy);
        final controlPoint2 = Offset(start.dx + (end.dx - start.dx) / 2, end.dy);
        path.cubicTo(controlPoint1.dx, controlPoint1.dy, controlPoint2.dx, controlPoint2.dy, end.dx, end.dy);
        canvas.drawPath(path, paint);

        // Draw connection dot
        canvas.drawCircle(start, 4, Paint()..color = _tealAccent..style = PaintingStyle.fill);
        canvas.drawCircle(end, 4, Paint()..color = _tealAccent..style = PaintingStyle.fill);
      }
    }

    if (draggingSource != null && draggingEndPos != null) {
      final start = Offset(draggingSource!.position.dx + 240, draggingSource!.position.dy + 35);
      final end = draggingEndPos!;

      final dragPaint = Paint()
        ..color = _tealAccent
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke;

      final path = Path();
      path.moveTo(start.dx, start.dy);
      final controlPoint1 = Offset(start.dx + (end.dx - start.dx) / 2, start.dy);
      final controlPoint2 = Offset(start.dx + (end.dx - start.dx) / 2, end.dy);
      path.cubicTo(controlPoint1.dx, controlPoint1.dy, controlPoint2.dx, controlPoint2.dy, end.dx, end.dy);
      canvas.drawPath(path, dragPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
