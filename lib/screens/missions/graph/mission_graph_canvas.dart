import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import 'mission_graph_models.dart';

/// Connection validation status during wire drag.
class ConnectionValidationResult {
  const ConnectionValidationResult.valid([this.successMessage = 'Valid connection'])
      : isValid = true,
        errorMessage = null;

  const ConnectionValidationResult.invalid(this.errorMessage)
      : isValid = false,
        successMessage = null;

  final bool isValid;
  final String? errorMessage;
  final String? successMessage;
}

/// Interactive Canvas for Node-Based Mission Editing.
class MissionGraphCanvas extends StatefulWidget {
  const MissionGraphCanvas({
    super.key,
    required this.graph,
    required this.selectedNode,
    required this.onSelectNode,
    required this.onGraphChanged,
    this.selectedEdge,
    this.onSelectEdge,
    this.onDeleteEdge,
    this.activeNodeId,
    this.readOnly = false,
    this.isRunning = false,
  });

  final MissionGraph graph;
  final GraphNode? selectedNode;
  final GraphEdge? selectedEdge;
  final ValueChanged<GraphNode?> onSelectNode;
  final ValueChanged<GraphEdge?>? onSelectEdge;
  final ValueChanged<GraphEdge>? onDeleteEdge;
  final VoidCallback onGraphChanged;
  final String? activeNodeId;
  final bool readOnly;
  final bool isRunning;

  @override
  State<MissionGraphCanvas> createState() => _MissionGraphCanvasState();
}

class _MissionGraphCanvasState extends State<MissionGraphCanvas>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformController = TransformationController();
  final GlobalKey _canvasKey = GlobalKey();
  late final AnimationController _flowAnimController;

  // Wire drawing state
  GraphNode? _drawingFromNode;
  NodePort? _drawingFromPort;
  bool? _drawingFromIsInput;
  Offset? _drawingCurrentPos;

  // Selected edge for deletion
  GraphEdge? _internalSelectedEdge;
  GraphEdge? get _selectedEdge => widget.selectedEdge ?? _internalSelectedEdge;

  void _setSelectedEdge(GraphEdge? edge) {
    setState(() {
      _internalSelectedEdge = edge;
    });
    widget.onSelectEdge?.call(edge);
  }

  void _deleteEdge(GraphEdge edge) {
    setState(() {
      widget.graph.edges.remove(edge);
      if (_internalSelectedEdge?.id == edge.id) {
        _internalSelectedEdge = null;
      }
    });
    widget.onDeleteEdge?.call(edge);
    widget.onGraphChanged();
  }

  // Port keys for exact layout measurement
  final Map<String, GlobalKey> _portKeys = {};

  // Map to store calculated port offsets on canvas
  final Map<String, Offset> _portOffsets = {};

  // Hovered target during wire drag
  (GraphNode, NodePort, bool)? _hoveredTarget;
  ConnectionValidationResult? _hoveredValidation;

  @override
  void initState() {
    super.initState();
    _flowAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updatePortOffsets());
  }

  @override
  void dispose() {
    _flowAnimController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MissionGraphCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.graph != widget.graph || oldWidget.graph.nodes.length != widget.graph.nodes.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updatePortOffsets());
    }
  }

  void _updatePortOffsets() {
    final canvasBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (canvasBox == null || !canvasBox.hasSize) return;

    bool changed = false;
    for (final entry in _portKeys.entries) {
      final portContext = entry.value.currentContext;
      if (portContext == null) continue;
      final portBox = portContext.findRenderObject() as RenderBox?;
      if (portBox == null || !portBox.hasSize) continue;

      final isInput = entry.key.contains('_in_');
      final localAnchor = Offset(
        isInput ? 9.0 : (portBox.size.width - 9.0),
        portBox.size.height / 2,
      );

      final globalPos = portBox.localToGlobal(localAnchor);
      final canvasPos = canvasBox.globalToLocal(globalPos);

      if (_portOffsets[entry.key] != canvasPos) {
        _portOffsets[entry.key] = canvasPos;
        changed = true;
      }
    }
    if (changed && mounted) {
      setState(() {});
    }
  }

  Offset _estimatePortOffset(GraphNode node, String portId, bool isInput) {
    double y = node.position.dy + 82.0;
    if (isInput) {
      final portIndex = node.inputPorts.indexWhere((p) => p.id == portId);
      if (portIndex > 0) y += portIndex * 26.0;
      return Offset(node.position.dx + 16.0, y);
    } else {
      final portIndex = node.outputPorts.indexWhere((p) => p.id == portId);
      if (portIndex > 0) y += portIndex * 26.0;
      return Offset(node.position.dx + 224.0, y);
    }
  }

  (GraphNode, NodePort, bool)? _findHoveredPort(Offset canvasPos) {
    // 1. Check if cursor is directly over or within snapping distance of any port handle
    double bestDistance = 32.0; // 32px snap radius around port handle
    (GraphNode, NodePort, bool)? bestPort;

    for (final node in widget.graph.nodes) {
      // Check input ports
      for (final port in node.inputPorts) {
        final key = '${node.id}_in_${port.id}';
        final offset = _portOffsets[key] ?? _estimatePortOffset(node, port.id, true);
        final dist = (offset - canvasPos).distance;
        if (dist < bestDistance) {
          bestDistance = dist;
          bestPort = (node, port, true);
        }
      }

      // Check output ports
      for (final port in node.outputPorts) {
        final key = '${node.id}_out_${port.id}';
        final offset = _portOffsets[key] ?? _estimatePortOffset(node, port.id, false);
        final dist = (offset - canvasPos).distance;
        if (dist < bestDistance) {
          bestDistance = dist;
          bestPort = (node, port, false);
        }
      }
    }

    if (bestPort != null) return bestPort;

    // 2. If not snapping directly to a port, check if cursor is over any node card
    for (final node in widget.graph.nodes) {
      final nodeRect = Rect.fromLTWH(node.position.dx, node.position.dy, 240, 160);
      if (nodeRect.contains(canvasPos)) {
        if (!(_drawingFromIsInput ?? false)) {
          // Dragging from output -> target this node's input port
          if (node.inputPorts.isNotEmpty) {
            return (node, node.inputPorts.first, true);
          } else {
            // Node has no input port (e.g. start node)
            return (node, const NodePort(id: 'in', label: 'In', isInput: true), true);
          }
        } else {
          // Dragging from input -> target closest output port on this node
          if (node.outputPorts.isNotEmpty) {
            NodePort closest = node.outputPorts.first;
            double minDist = double.infinity;
            for (final op in node.outputPorts) {
              final k = '${node.id}_out_${op.id}';
              final off = _portOffsets[k] ?? _estimatePortOffset(node, op.id, false);
              final d = (off - canvasPos).distance;
              if (d < minDist) {
                minDist = d;
                closest = op;
              }
            }
            return (node, closest, false);
          }
        }
      }
    }

    return null;
  }

  ConnectionValidationResult _validateConnection({
    required GraphNode fromNode,
    required NodePort fromPort,
    required bool fromIsInput,
    required GraphNode toNode,
    required NodePort toPort,
    required bool toIsInput,
  }) {
    // 1. Same node validation
    if (fromNode.id == toNode.id) {
      return const ConnectionValidationResult.invalid('Cannot connect a step to itself');
    }

    // 2. Direction compatibility
    if (fromIsInput == toIsInput) {
      if (fromIsInput) {
        return const ConnectionValidationResult.invalid('Cannot connect input to input (connect to an Output)');
      } else {
        return const ConnectionValidationResult.invalid('Cannot connect output to output (connect to an Input)');
      }
    }

    // Normalize so that actual source is output and destination is input
    final outNode = fromIsInput ? toNode : fromNode;
    final outPort = fromIsInput ? toPort : fromPort;
    final inNode = fromIsInput ? fromNode : toNode;
    final inPort = fromIsInput ? fromPort : toPort;

    // 3. Start node cannot receive incoming connections
    if (inNode.type == 'start') {
      return const ConnectionValidationResult.invalid('Start step cannot have incoming connections');
    }

    // 4. Target node must accept inputs
    if (inNode.inputPorts.isEmpty) {
      final name = inNode.label.isNotEmpty ? inNode.label : inNode.id;
      return ConnectionValidationResult.invalid('Step "$name" does not accept incoming connections');
    }

    // 5. Finish node cannot have outgoing connections
    if (outNode.type == 'end' || outNode.type == 'mission_end') {
      return const ConnectionValidationResult.invalid('Finish step cannot have outgoing connections');
    }

    // 6. Duplicate connection check
    final alreadyExists = widget.graph.edges.any((e) =>
      e.fromNode == outNode.id &&
      e.fromPort == outPort.id &&
      e.toNode == inNode.id &&
      e.toPort == inPort.id
    );
    if (alreadyExists) {
      return const ConnectionValidationResult.invalid('Connection already exists between these steps');
    }

    final fromTitle = outNode.label.isNotEmpty ? outNode.label : outNode.id;
    final toTitle = inNode.label.isNotEmpty ? inNode.label : inNode.id;
    return ConnectionValidationResult.valid('Connect "$fromTitle" (${outPort.label}) → "$toTitle"');
  }

  static List<Offset> _getOrthogonalPoints(
    Offset p1,
    Offset p2, {
    double corridorOffset = 0.0,
    double loopLaneOffset = 0.0,
  }) {
    final dx = p2.dx - p1.dx;

    // 1. Long-span forward jump (spans across 2 or more columns)
    // Route via an obstacle-free bottom gutter channel so it NEVER slices through intermediate node cards!
    if (dx >= 380.0) {
      final gutterY = math.max(p1.dy, p2.dy) + 95.0 + loopLaneOffset + (corridorOffset * 0.5);
      final exitX = p1.dx + 26.0;
      final enterX = p2.dx - 26.0;
      return [
        p1,
        Offset(exitX, p1.dy),
        Offset(exitX, gutterY),
        Offset(enterX, gutterY),
        Offset(enterX, p2.dy),
        p2,
      ];
    } else if (dx >= 48.0) {
      // 2. Adjacent or near column: clean vertical step in the inter-column corridor
      final midX = ((p1.dx + p2.dx) / 2.0) + corridorOffset;
      return [
        p1,
        Offset(midX, p1.dy),
        Offset(midX, p2.dy),
        p2,
      ];
    } else {
      // 3. Loopback / reverse edge
      final exitX = p1.dx + 30.0 + (loopLaneOffset > 0 ? loopLaneOffset : 0.0);
      final enterX = p2.dx - 30.0 - (loopLaneOffset < 0 ? -loopLaneOffset : loopLaneOffset);
      final double midY;
      if ((p2.dy - p1.dy).abs() > 30.0) {
        midY = ((p1.dy + p2.dy) / 2.0) + loopLaneOffset;
      } else {
        midY = p1.dy + 80.0 + loopLaneOffset;
      }
      return [
        p1,
        Offset(exitX, p1.dy),
        Offset(exitX, midY),
        Offset(enterX, midY),
        Offset(enterX, p2.dy),
        p2,
      ];
    }
  }

  static double _distToSegment(Offset p, Offset a, Offset b) {
    final l2 = (b - a).distanceSquared;
    if (l2 == 0.0) return (p - a).distance;
    final t = math.max(0.0, math.min(1.0, ((p.dx - a.dx) * (b.dx - a.dx) + (p.dy - a.dy) * (b.dy - a.dy)) / l2));
    final projection = Offset(a.dx + t * (b.dx - a.dx), a.dy + t * (b.dy - a.dy));
    return (p - projection).distance;
  }

  static bool _isPointNearOrthogonal(
    Offset pt,
    Offset p1,
    Offset p2,
    double threshold, {
    double corridorOffset = 0.0,
    double loopLaneOffset = 0.0,
  }) {
    final points = _getOrthogonalPoints(
      p1,
      p2,
      corridorOffset: corridorOffset,
      loopLaneOffset: loopLaneOffset,
    );
    for (int i = 0; i < points.length - 1; i++) {
      if (_distToSegment(pt, points[i], points[i + 1]) <= threshold) {
        return true;
      }
    }
    return false;
  }

  static Offset _getOrthogonalMidpoint(
    Offset p1,
    Offset p2, {
    double corridorOffset = 0.0,
    double loopLaneOffset = 0.0,
  }) {
    final points = _getOrthogonalPoints(
      p1,
      p2,
      corridorOffset: corridorOffset,
      loopLaneOffset: loopLaneOffset,
    );
    double totalLen = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      totalLen += (points[i + 1] - points[i]).distance;
    }
    if (totalLen == 0.0) return (p1 + p2) / 2.0;
    final targetLen = totalLen / 2.0;
    double accum = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      final segLen = (points[i + 1] - points[i]).distance;
      if (accum + segLen >= targetLen) {
        final fraction = segLen > 0 ? (targetLen - accum) / segLen : 0.0;
        return Offset(
          points[i].dx + fraction * (points[i + 1].dx - points[i].dx),
          points[i].dy + fraction * (points[i + 1].dy - points[i].dy),
        );
      }
      accum += segLen;
    }
    return (p1 + p2) / 2.0;
  }

  static Path _buildSmoothPath(List<Offset> points, double radius) {
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points.first.dx, points.first.dy);
    if (points.length <= 2) {
      if (points.length == 2) path.lineTo(points[1].dx, points[1].dy);
      return path;
    }

    for (int i = 1; i < points.length - 1; i++) {
      final pPrev = points[i - 1];
      final pCurr = points[i];
      final pNext = points[i + 1];

      final v1 = pCurr - pPrev;
      final v2 = pNext - pCurr;
      final len1 = v1.distance;
      final len2 = v2.distance;

      if (len1 < 0.001 || len2 < 0.001) {
        path.lineTo(pCurr.dx, pCurr.dy);
        continue;
      }

      final r = math.min(radius, math.min(len1 / 2.0, len2 / 2.0));
      final u1 = v1 / len1;
      final u2 = v2 / len2;

      final startCurve = pCurr - (u1 * r);
      final endCurve = pCurr + (u2 * r);

      path.lineTo(startCurve.dx, startCurve.dy);
      path.quadraticBezierTo(pCurr.dx, pCurr.dy, endCurve.dx, endCurve.dy);
    }

    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  Map<String, _EdgeRouteLayout> _calculateEdgeLayouts() {
    final sourceGroups = <String, List<GraphEdge>>{};
    final targetGroups = <String, List<GraphEdge>>{};

    for (final edge in widget.graph.edges) {
      final fromKey = '${edge.fromNode}_out_${edge.fromPort}';
      final toKey = '${edge.toNode}_in_${edge.toPort}';
      sourceGroups.putIfAbsent(fromKey, () => []).add(edge);
      targetGroups.putIfAbsent(toKey, () => []).add(edge);
    }

    final forwardCorridors = <String, List<GraphEdge>>{};
    final loopbackEdges = <GraphEdge>[];
    final nominalP1 = <String, Offset>{};
    final nominalP2 = <String, Offset>{};

    for (final edge in widget.graph.edges) {
      final fromKey = '${edge.fromNode}_out_${edge.fromPort}';
      final toKey = '${edge.toNode}_in_${edge.toPort}';

      final fromNode = widget.graph.nodes.firstWhere(
        (n) => n.id == edge.fromNode,
        orElse: () => GraphNode(id: '', type: '', position: Offset.zero),
      );
      final toNode = widget.graph.nodes.firstWhere(
        (n) => n.id == edge.toNode,
        orElse: () => GraphNode(id: '', type: '', position: Offset.zero),
      );

      final baseP1 = _portOffsets[fromKey] ?? _estimatePortOffset(fromNode, edge.fromPort, false);
      final baseP2 = _portOffsets[toKey] ?? _estimatePortOffset(toNode, edge.toPort, true);

      final outList = sourceGroups[fromKey] ?? [edge];
      final inList = targetGroups[toKey] ?? [edge];

      final sourceSlotOffset = outList.length > 1
          ? (outList.indexOf(edge) - (outList.length - 1) / 2.0) * 12.0
          : 0.0;
      final targetSlotOffset = inList.length > 1
          ? (inList.indexOf(edge) - (inList.length - 1) / 2.0) * 14.0
          : 0.0;

      final p1 = Offset(baseP1.dx, baseP1.dy + sourceSlotOffset);
      final p2 = Offset(baseP2.dx, baseP2.dy + targetSlotOffset);
      nominalP1[edge.id] = p1;
      nominalP2[edge.id] = p2;

      if (p2.dx >= p1.dx + 48.0) {
        final fromCol = (p1.dx / 200.0).round();
        final toCol = (p2.dx / 200.0).round();
        final corridorKey = '$fromCol->$toCol';
        forwardCorridors.putIfAbsent(corridorKey, () => []).add(edge);
      } else {
        loopbackEdges.add(edge);
      }
    }

    final layouts = <String, _EdgeRouteLayout>{};
    for (final edge in widget.graph.edges) {
      final p1 = nominalP1[edge.id] ?? Offset.zero;
      final p2 = nominalP2[edge.id] ?? Offset.zero;
      final fromKey = '${edge.fromNode}_out_${edge.fromPort}';
      final toKey = '${edge.toNode}_in_${edge.toPort}';

      final totalInSource = sourceGroups[fromKey]?.length ?? 1;
      final totalInTarget = targetGroups[toKey]?.length ?? 1;

      double corridorOffset = 0.0;
      double loopLaneOffset = 0.0;

      if (p2.dx >= p1.dx + 48.0) {
        final fromCol = (p1.dx / 200.0).round();
        final toCol = (p2.dx / 200.0).round();
        final corridorKey = '$fromCol->$toCol';
        final cList = forwardCorridors[corridorKey] ?? [edge];
        if (cList.length > 1) {
          final idx = cList.indexOf(edge);
          corridorOffset = (idx - (cList.length - 1) / 2.0) * 16.0;
        }
      } else {
        if (loopbackEdges.length > 1) {
          final idx = loopbackEdges.indexOf(edge);
          loopLaneOffset = (idx - (loopbackEdges.length - 1) / 2.0) * 18.0;
        }
      }

      layouts[edge.id] = _EdgeRouteLayout(
        p1: p1,
        p2: p2,
        corridorOffset: corridorOffset,
        loopLaneOffset: loopLaneOffset,
        totalInSource: totalInSource,
        totalInTarget: totalInTarget,
      );
    }

    return layouts;
  }

  Widget _buildSelectedEdgeBadge(GraphEdge edge) {
    final layouts = _calculateEdgeLayouts();
    final layout = layouts[edge.id];
    final fromKey = '${edge.fromNode}_out_${edge.fromPort}';
    final toKey = '${edge.toNode}_in_${edge.toPort}';
    final fromNode = widget.graph.nodes.firstWhere(
      (n) => n.id == edge.fromNode,
      orElse: () => GraphNode(id: '', type: '', position: Offset.zero),
    );
    final toNode = widget.graph.nodes.firstWhere(
      (n) => n.id == edge.toNode,
      orElse: () => GraphNode(id: '', type: '', position: Offset.zero),
    );
    final p1 = layout?.p1 ?? (_portOffsets[fromKey] ?? _estimatePortOffset(fromNode, edge.fromPort, false));
    final p2 = layout?.p2 ?? (_portOffsets[toKey] ?? _estimatePortOffset(toNode, edge.toPort, true));
    final mid = _getOrthogonalMidpoint(
      p1,
      p2,
      corridorOffset: layout?.corridorOffset ?? 0.0,
      loopLaneOffset: layout?.loopLaneOffset ?? 0.0,
    );

    return Positioned(
      left: mid.dx - 18,
      top: mid.dy - 18,
      child: Tooltip(
        message: 'Delete Connection Line (Del / Backspace)',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _deleteEdge(edge),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.danger,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.danger.withValues(alpha: 0.5),
                    blurRadius: 10,
                    spreadRadius: 2,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Center(
                child: Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWireValidationBanner() {
    if (_drawingFromNode == null || _drawingFromPort == null) return const SizedBox.shrink();

    final valResult = _hoveredValidation;

    final isValid = valResult?.isValid;
    final color = isValid == true
        ? AppColors.success
        : isValid == false
            ? AppColors.danger
            : AppColors.primary;
    final icon = isValid == true
        ? Icons.check_circle_rounded
        : isValid == false
            ? Icons.cancel_rounded
            : Icons.cable_rounded;

    final text = valResult?.isValid == true
        ? (valResult!.successMessage ?? 'Valid connection - Release to connect')
        : valResult?.isValid == false
            ? (valResult!.errorMessage ?? 'Cannot connect here')
            : 'Connecting from "${_drawingFromNode!.label.isNotEmpty ? _drawingFromNode!.label : _drawingFromNode!.id}" (${_drawingFromPort!.label}) — drag to an ${_drawingFromIsInput == true ? "Output" : "Input"} port';

    return Positioned(
      top: 16,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: color, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 14,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Text(
                text,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updatePortOffsets());

    return Container(
      color: AppColors.background,
      child: Stack(
        children: [
          // Infinite Grid + Edge Wire Painter
          InteractiveViewer(
            transformationController: _transformController,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(3000),
            minScale: 0.2,
            maxScale: 2.5,
            child: GestureDetector(
              onTapUp: (details) {
                final tapPos = details.localPosition;
                GraphEdge? clickedEdge;
                final layouts = _calculateEdgeLayouts();
                for (final edge in widget.graph.edges) {
                  final layout = layouts[edge.id];
                  if (layout == null) continue;
                  if (_isPointNearOrthogonal(
                    tapPos,
                    layout.p1,
                    layout.p2,
                    22.0,
                    corridorOffset: layout.corridorOffset,
                    loopLaneOffset: layout.loopLaneOffset,
                  )) {
                    clickedEdge = edge;
                    break;
                  }
                }
                if (clickedEdge != null) {
                  _setSelectedEdge(clickedEdge);
                  widget.onSelectNode(null);
                } else {
                  _setSelectedEdge(null);
                  widget.onSelectNode(null);
                }
              },
              child: SizedBox(
                key: _canvasKey,
                width: 5000,
                height: 5000,
                child: Stack(
                  children: [
                    // Grid background
                    const Positioned.fill(
                      child: CustomPaint(painter: _GridBackgroundPainter()),
                    ),

                    // Edges & In-Progress Wire
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _flowAnimController,
                        builder: (context, _) {
                          return CustomPaint(
                            painter: _EdgesPainter(
                              graph: widget.graph,
                              portOffsets: _portOffsets,
                              edgeLayouts: _calculateEdgeLayouts(),
                              selectedEdge: _selectedEdge,
                              activeNodeId: widget.activeNodeId,
                              animProgress: _flowAnimController.value,
                              isRunning: widget.isRunning,
                              drawingFromOffset: _drawingFromPort != null
                                  ? (_portOffsets['${_drawingFromNode!.id}_${_drawingFromIsInput == true ? 'in' : 'out'}_${_drawingFromPort!.id}'] ??
                                      _estimatePortOffset(_drawingFromNode!, _drawingFromPort!.id, _drawingFromIsInput ?? false))
                                  : null,
                              drawingCurrentOffset: _drawingCurrentPos != null && _hoveredTarget != null && (_hoveredValidation?.isValid ?? false)
                                  ? (_portOffsets['${_hoveredTarget!.$1.id}_${_hoveredTarget!.$3 ? 'in' : 'out'}_${_hoveredTarget!.$2.id}'] ??
                                      _estimatePortOffset(_hoveredTarget!.$1, _hoveredTarget!.$2.id, _hoveredTarget!.$3))
                                  : _drawingCurrentPos,
                              drawingFromIsInput: _drawingFromIsInput ?? false,
                              drawingColor: _drawingFromPort?.color ?? AppColors.primary,
                              isValidTarget: _hoveredTarget != null ? (_hoveredValidation?.isValid ?? false) : null,
                            ),
                          );
                        },
                      ),
                    ),

                    // Node Widgets
                    for (final node in widget.graph.nodes)
                      _buildNodeWidget(node),

                    // Floating Delete Badge on Selected Edge
                    if (_selectedEdge != null && !widget.readOnly)
                      _buildSelectedEdgeBadge(_selectedEdge!),
                  ],
                ),
              ),
            ),
          ),

          // Wire In-Progress Floating Validation Banner
          _buildWireValidationBanner(),

          // Edge Deletion Quick Banner
          if (_selectedEdge != null && !widget.readOnly)
            Positioned(
              top: 16,
              left: 16,
              child: Card(
                color: AppColors.surface,
                elevation: 4,
                shadowColor: AppColors.shadowTint.withValues(alpha: 0.15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.danger),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.link_off, color: AppColors.danger, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Connection selected: ${_selectedEdge!.fromNode} (${_selectedEdge!.fromPort}) → ${_selectedEdge!.toNode}',
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.danger,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () {
                          if (_selectedEdge != null) {
                            _deleteEdge(_selectedEdge!);
                          }
                        },
                        icon: const Icon(Icons.delete_outline, size: 14),
                        label: const Text('Delete Edge'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
                        onPressed: () => _setSelectedEdge(null),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Canvas Controls (Zoom In, Zoom Out, Reset)
          // Positioned at bottom-left so it never overlaps with the AI Mission Assistant at bottom-right
          Positioned(
            bottom: 16,
            left: 16,
            child: Card(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.border),
              ),
              elevation: 3,
              shadowColor: AppColors.shadowTint.withValues(alpha: 0.14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.add, color: AppColors.textPrimary, size: 20),
                    tooltip: 'Zoom In',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      final matrix = _transformController.value.clone();
                      matrix.scaleByDouble(1.2, 1.2, 1.0, 1.0);
                      _transformController.value = matrix;
                    },
                  ),
                  const Divider(height: 1, thickness: 1, color: AppColors.border),
                  IconButton(
                    icon: const Icon(Icons.remove, color: AppColors.textPrimary, size: 20),
                    tooltip: 'Zoom Out',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      final matrix = _transformController.value.clone();
                      matrix.scaleByDouble(0.8, 0.8, 1.0, 1.0);
                      _transformController.value = matrix;
                    },
                  ),
                  const Divider(height: 1, thickness: 1, color: AppColors.border),
                  IconButton(
                    icon: const Icon(Icons.center_focus_strong, color: AppColors.textPrimary, size: 18),
                    tooltip: 'Reset View',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _transformController.value = Matrix4.identity();
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeWidget(GraphNode node) {
    final isSelected = widget.selectedNode?.id == node.id;
    final isActive = widget.activeNodeId == node.id;

    // Node Dimension Constants
    const double nodeWidth = 260.0;

    if (isActive) {
      return Positioned(
        left: node.position.dx,
        top: node.position.dy,
        child: AnimatedBuilder(
          animation: _flowAnimController,
          builder: (context, _) {
            final pulse = (math.sin(_flowAnimController.value * 2 * math.pi) + 1.0) / 2.0;
            return _buildNodeCard(
              node,
              isSelected: isSelected,
              isActive: true,
              pulse: pulse,
              nodeWidth: nodeWidth,
            );
          },
        ),
      );
    }

    return Positioned(
      left: node.position.dx,
      top: node.position.dy,
      child: _buildNodeCard(
        node,
        isSelected: isSelected,
        isActive: false,
        pulse: 0.0,
        nodeWidth: nodeWidth,
      ),
    );
  }

  Widget _buildNodeCard(
    GraphNode node, {
    required bool isSelected,
    required bool isActive,
    required double pulse,
    required double nodeWidth,
  }) {
    final glowAlpha = 0.25 + 0.35 * pulse;
    final glowBlur = 12.0 + 8.0 * pulse;
    final glowSpread = 1.0 + 2.0 * pulse;

    return GestureDetector(
      onPanUpdate: widget.readOnly
          ? null
          : (details) {
              setState(() {
                node.position += details.delta;
                for (final p in node.inputPorts) {
                  final k = '${node.id}_in_${p.id}';
                  if (_portOffsets.containsKey(k)) {
                    _portOffsets[k] = _portOffsets[k]! + details.delta;
                  }
                }
                for (final p in node.outputPorts) {
                  final k = '${node.id}_out_${p.id}';
                  if (_portOffsets.containsKey(k)) {
                    _portOffsets[k] = _portOffsets[k]! + details.delta;
                  }
                }
              });
              widget.onGraphChanged();
            },
      onTap: () {
        widget.onSelectNode(node);
        _setSelectedEdge(null);
      },
      child: Container(
        width: nodeWidth,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive
                ? Color.lerp(AppColors.primary, AppColors.primaryLight, pulse)!
                : isSelected
                    ? AppColors.primary
                    : AppColors.border,
            width: isActive ? 2.5 : isSelected ? 2.0 : 1.2,
          ),
          boxShadow: [
            if (isActive) ...[
              BoxShadow(
                color: AppColors.primary.withValues(alpha: glowAlpha),
                blurRadius: glowBlur,
                spreadRadius: glowSpread,
              ),
              BoxShadow(
                color: AppColors.primaryLight.withValues(alpha: 0.15 * pulse),
                blurRadius: glowBlur * 1.5,
                spreadRadius: glowSpread * 1.5,
              ),
            ] else if (isSelected)
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.22),
                blurRadius: 14,
                offset: const Offset(0, 3),
              )
            else
              BoxShadow(
                color: AppColors.shadowTint.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Node Header
            _buildNodeHeader(node, isActive),

            // Node Body / Summary
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: _buildNodeSummary(node),
            ),

            const Divider(height: 1, color: AppColors.border),

            // Ports Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Input Port
                  if (node.inputPorts.isNotEmpty)
                    _buildPortWidget(
                      node: node,
                      port: node.inputPorts.first,
                      isInput: true,
                    )
                  else
                    const SizedBox(width: 12),

                  const SizedBox(width: 6),

                  // Output Ports Column (flexible to prevent RenderFlex overflow on long port labels)
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final outPort in node.outputPorts)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _buildPortWidget(
                              node: node,
                              port: outPort,
                              isInput: false,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNodeHeader(GraphNode node, bool isActive) {
    String categoryTitle;
    IconData icon;
    Color categoryColor;

    switch (node.type) {
      case 'start':
        categoryTitle = 'Trigger';
        icon = Icons.bolt_rounded;
        categoryColor = AppColors.success;
        break;
      case 'end':
      case 'mission_end':
        categoryTitle = 'Terminal';
        icon = Icons.stop_rounded;
        categoryColor = const Color(0xFFDC2626);
        break;
      case 'navigate_waypoint':
        categoryTitle = 'Navigation';
        icon = Icons.navigation_rounded;
        categoryColor = const Color(0xFF2563EB);
        break;
      case 'navigate_coordinates':
        categoryTitle = 'Coordinates';
        icon = Icons.explore_rounded;
        categoryColor = const Color(0xFF2563EB);
        break;
      case 'patrol_loop':
        categoryTitle = 'Patrol Loop';
        icon = Icons.sync_rounded;
        categoryColor = const Color(0xFF3B82F6);
        break;
      case 'relocalize':
        categoryTitle = 'Localization';
        icon = Icons.my_location_rounded;
        categoryColor = const Color(0xFF0284C7);
        break;
      case 'cancel_navigation':
        categoryTitle = 'Navigation';
        icon = Icons.cancel_rounded;
        categoryColor = const Color(0xFFDC2626);
        break;
      case 'wait':
        categoryTitle = 'Timing';
        icon = Icons.timer_outlined;
        categoryColor = AppColors.warning;
        break;
      case 'dock':
        categoryTitle = 'Power & Dock';
        icon = Icons.battery_charging_full_rounded;
        categoryColor = const Color(0xFF16A34A);
        break;
      case 'undock':
        categoryTitle = 'Power & Dock';
        icon = Icons.power_settings_new_rounded;
        categoryColor = const Color(0xFF059669);
        break;
      case 'jog_motion':
        categoryTitle = 'Actuator';
        icon = Icons.gamepad_outlined;
        categoryColor = const Color(0xFFD97706);
        break;
      case 'emergency_stop':
        categoryTitle = 'Safety';
        icon = Icons.emergency_rounded;
        categoryColor = const Color(0xFFDC2626);
        break;
      case 'loop':
      case 'loop_counter':
        categoryTitle = 'Logic Flow';
        icon = Icons.loop_rounded;
        categoryColor = const Color(0xFF7C3AED);
        break;
      case 'condition':
        categoryTitle = 'Branch Logic';
        icon = Icons.call_split_rounded;
        categoryColor = const Color(0xFFEA580C);
        break;
      case 'parallel':
      case 'parallel_fork':
        categoryTitle = 'Parallel Flow';
        icon = Icons.alt_route_rounded;
        categoryColor = const Color(0xFF00ACC1);
        break;
      case 'battery_guard':
        categoryTitle = 'Safety Guard';
        icon = Icons.battery_saver_rounded;
        categoryColor = const Color(0xFF059669);
        break;
      case 'set_variable':
        categoryTitle = 'Variables';
        icon = Icons.data_object_rounded;
        categoryColor = const Color(0xFF9333EA);
        break;
      case 'ui_interaction':
        categoryTitle = 'Kiosk Form';
        icon = Icons.touch_app_rounded;
        categoryColor = AppColors.primary;
        break;
      case 'ui_notification':
        categoryTitle = 'Kiosk Alert';
        icon = Icons.notifications_active_rounded;
        categoryColor = const Color(0xFF0284C7);
        break;
      case 'ui_choice':
        categoryTitle = 'Kiosk Dialog';
        icon = Icons.ads_click_rounded;
        categoryColor = AppColors.primary;
        break;
      case 'ui_media':
        categoryTitle = 'Kiosk Media';
        icon = Icons.smart_display_rounded;
        categoryColor = const Color(0xFF0284C7);
        break;
      case 'ui_speech':
        categoryTitle = 'Voice TTS';
        icon = Icons.record_voice_over_rounded;
        categoryColor = const Color(0xFF8B5CF6);
        break;
      case 'notify':
        categoryTitle = 'Robot Signal';
        icon = Icons.lightbulb_rounded;
        categoryColor = const Color(0xFF0D9488);
        break;
      case 'call_api':
        categoryTitle = 'Webhook & API';
        icon = Icons.http_rounded;
        categoryColor = const Color(0xFF7C3AED);
        break;
      case 'call_service':
        categoryTitle = 'ROS 2 Service';
        icon = Icons.precision_manufacturing_rounded;
        categoryColor = const Color(0xFF4F46E5);
        break;
      case 'call_action':
        categoryTitle = 'ROS 2 Action';
        icon = Icons.settings_input_component_rounded;
        categoryColor = const Color(0xFF4F46E5);
        break;
      case 'publish_topic':
        categoryTitle = 'ROS 2 Topic';
        icon = Icons.podcasts_rounded;
        categoryColor = const Color(0xFF4F46E5);
        break;
      case 'switch_mission':
      case 'redirect_mission':
        categoryTitle = 'Workflow';
        icon = Icons.shuffle_rounded;
        categoryColor = const Color(0xFF009688);
        break;
      default:
        categoryTitle = 'Step';
        icon = Icons.circle_outlined;
        categoryColor = AppColors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(13),
          topRight: Radius.circular(13),
        ),
        border: Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: [
          // n8n-style category squircle icon container
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: categoryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: categoryColor.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: Center(
              child: Icon(icon, size: 17, color: categoryColor),
            ),
          ),
          const SizedBox(width: 9),
          // Category tag + Node title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  categoryTitle.toUpperCase(),
                  style: TextStyle(
                    color: categoryColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1.5),
                Text(
                  node.label.isNotEmpty ? node.label : node.type,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Status indicator or Delete action
          if (isActive && widget.isRunning)
            AnimatedBuilder(
              animation: _flowAnimController,
              builder: (context, _) {
                final pulse = (math.sin(_flowAnimController.value * 2 * math.pi) + 1.0) / 2.0;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12 + 0.1 * pulse),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.4 + 0.4 * pulse),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.success.withValues(alpha: 0.3 * pulse),
                        blurRadius: 6 * pulse,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.success,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.success.withValues(alpha: 0.8),
                              blurRadius: 3 + 2 * pulse,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'RUNNING',
                        style: TextStyle(
                          color: AppColors.success,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                );
              },
            )
          else if (!widget.readOnly && node.type != 'start')
            InkWell(
              onTap: () {
                setState(() {
                  widget.graph.nodes.remove(node);
                  widget.graph.edges.removeWhere(
                      (e) => e.fromNode == node.id || e.toNode == node.id);
                  if (widget.graph.entrypoint == node.id) {
                    widget.graph.entrypoint =
                        widget.graph.nodes.isNotEmpty ? widget.graph.nodes.first.id : null;
                  }
                  if (widget.selectedNode?.id == node.id) {
                    widget.onSelectNode(null);
                  }
                });
                widget.onGraphChanged();
              },
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.all(4.0),
                child: Icon(Icons.close_rounded, size: 15, color: AppColors.textTertiary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNodeSummary(GraphNode node) {
    String summary = '';
    switch (node.type) {
      case 'start':
        final trigger = node.params['trigger'] as String? ?? 'manual';
        final enabled = node.params['enabled'] != false;
        if (trigger == 'interval') {
          final mins = (node.params['interval_minutes'] as num?)?.toInt() ?? 30;
          final h = mins ~/ 60;
          final m = mins % 60;
          final dStr = h > 0 ? (m > 0 ? '${h}h ${m}m' : '${h}h') : '${m}m';
          summary = enabled ? '⏰ Every $dStr ($mins min)' : '⏸ Every $dStr (Paused)';
        } else if (trigger == 'schedule') {
          final hour = (node.params['schedule_hour'] as num?)?.toInt() ?? 9;
          final min = (node.params['schedule_minute'] as num?)?.toInt() ?? 0;
          final rep = node.params['schedule_type'] as String? ?? 'daily';
          final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
          final amPm = hour >= 12 ? 'PM' : 'AM';
          final tStr = '$h12:${min.toString().padLeft(2, '0')} $amPm';
          summary = enabled ? '⏰ $rep at $tStr' : '⏸ $rep at $tStr (Paused)';
        } else {
          summary = '▶ On-demand / manual start';
        }
        break;
      case 'end':
      case 'mission_end':
        summary = node.params['dock_on_end'] == true
            ? 'Finish & return to charger'
            : 'Finish mission safely';
        break;
      case 'navigate_waypoint':
        final wp = node.params['waypoint']?.toString() ?? '';
        summary = wp.isNotEmpty ? 'Drive to: $wp' : 'Pick a destination in settings';
        break;
      case 'navigate_coordinates':
        summary = 'Drive to X: ${node.params['x'] ?? 0}, Y: ${node.params['y'] ?? 0}';
        break;
      case 'patrol_loop':
        final wps = (node.params['waypoints'] as List?)?.length ?? 0;
        final laps = node.params['laps'] ?? 1;
        summary = 'Visit $wps places in order ($laps laps)';
        break;
      case 'relocalize':
        summary = 'Scan room with laser to find position';
        break;
      case 'cancel_navigation':
        summary = 'Stop robot movement immediately';
        break;
      case 'wait':
        final sec = node.params['duration_sec'] ?? node.params['duration'] ?? 5;
        summary = 'Pause and wait $sec seconds';
        break;
      case 'dock':
        summary = 'Drive to charger and plug in';
        break;
      case 'undock':
        summary = 'Safely back away from charger';
        break;
      case 'jog_motion':
        final dur = node.params['duration_sec'] ?? 1.0;
        summary = 'Nudge / drive wheels for ${dur}s';
        break;
      case 'emergency_stop':
        summary = 'Safety stop (cut motor power)';
        break;
      case 'loop':
      case 'loop_counter':
        final count = node.params['count'] ?? 3;
        summary = 'Repeat connected steps $count times';
        break;
      case 'condition':
        final expr = node.params['expression'] ?? 'true';
        summary = 'Check if: $expr';
        break;
      case 'parallel':
      case 'parallel_fork':
        final bc = (node.params['branch_count'] as num?)?.toInt() ?? 2;
        summary = 'Run $bc steps at the same time';
        break;
      case 'battery_guard':
        final minB = node.params['min_battery_pct'] ?? 20;
        summary = 'Check if battery is at least $minB%';
        break;
      case 'set_variable':
        final varName = node.params['variable_name'] ?? 'var';
        final val = node.params['value'] ?? '';
        summary = 'Remember: $varName = $val';
        break;
      case 'call_api':
        final method = node.params['method'] ?? 'POST';
        final url = node.params['url']?.toString() ?? '';
        summary = '$method $url'.trim();
        if (summary.isEmpty) summary = 'Send web notification';
        break;
      case 'call_service':
        final srv = node.params['service_name']?.toString() ?? '';
        summary = srv.isNotEmpty ? 'Run command: $srv' : 'Trigger robot command';
        break;
      case 'call_action':
        final act = node.params['action_name']?.toString() ?? '';
        summary = act.isNotEmpty ? 'Run task: $act' : 'Run background task';
        break;
      case 'publish_topic':
        final top = node.params['topic_name']?.toString() ?? '';
        summary = top.isNotEmpty ? 'Broadcast to: $top' : 'Broadcast live signal';
        break;
      case 'ui_interaction':
        final title = node.params['title'] ?? 'Form';
        summary = 'Show form on screen: $title';
        break;
      case 'ui_notification':
        final title = node.params['title'] ?? 'Notice';
        summary = 'Show notice: $title';
        break;
      case 'ui_choice':
        final title = node.params['title'] ?? 'Question';
        summary = 'Ask buttons: $title';
        break;
      case 'ui_media':
        final mtype = node.params['media_type'] ?? 'media';
        summary = 'Show $mtype on robot screen';
        break;
      case 'ui_speech':
        final text = node.params['text'] ?? '';
        summary = text.isNotEmpty ? 'Say: "$text"' : 'Speak announcement aloud';
        break;
      case 'switch_mission':
      case 'redirect_mission':
        final target = (node.params['target_mission_id'] ?? node.params['mission_id'])?.toString() ?? '';
        summary = target.isNotEmpty ? 'Switch to mission: $target' : 'Switch to another saved mission';
        break;
      case 'notify':
        summary = node.params['oled_text'] ?? 'Sound chime & flash lights';
        break;
      default:
        summary = 'Execute step';
    }

    return Text(
      summary,
      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildPortWidget({
    required GraphNode node,
    required NodePort port,
    required bool isInput,
  }) {
    final portKey = '${node.id}_${isInput ? 'in' : 'out'}_${port.id}';
    final gKey = _portKeys.putIfAbsent(portKey, () => GlobalKey());

    final isBeingDrawnFrom = _drawingFromNode?.id == node.id &&
        _drawingFromPort?.id == port.id &&
        _drawingFromIsInput == isInput;

    final isHovered = _hoveredTarget != null &&
        _hoveredTarget!.$1.id == node.id &&
        _hoveredTarget!.$2.id == port.id &&
        _hoveredTarget!.$3 == isInput;

    final isHoverValid = isHovered && (_hoveredValidation?.isValid ?? false);
    final isHoverInvalid = isHovered && !(_hoveredValidation?.isValid ?? true);

    Color activeColor = port.color;
    if (isHoverValid) {
      activeColor = AppColors.success;
    } else if (isHoverInvalid) {
      activeColor = AppColors.danger;
    } else if (isBeingDrawnFrom) {
      activeColor = AppColors.primary;
    }

    return KeyedSubtree(
      key: gKey,
      child: GestureDetector(
        onPanStart: widget.readOnly
            ? null
            : (details) {
                setState(() {
                  _drawingFromNode = node;
                  _drawingFromPort = port;
                  _drawingFromIsInput = isInput;
                  _drawingCurrentPos = _portOffsets[portKey] ?? _estimatePortOffset(node, port.id, isInput);
                  _hoveredTarget = null;
                  _hoveredValidation = null;
                });
              },
        onPanUpdate: widget.readOnly
            ? null
            : (details) {
                setState(() {
                  _drawingCurrentPos = (_drawingCurrentPos ?? node.position) + details.delta;
                  final hovered = _findHoveredPort(_drawingCurrentPos!);
                  _hoveredTarget = hovered;
                  if (hovered != null && _drawingFromNode != null && _drawingFromPort != null) {
                    _hoveredValidation = _validateConnection(
                      fromNode: _drawingFromNode!,
                      fromPort: _drawingFromPort!,
                      fromIsInput: _drawingFromIsInput ?? false,
                      toNode: hovered.$1,
                      toPort: hovered.$2,
                      toIsInput: hovered.$3,
                    );
                  } else {
                    _hoveredValidation = null;
                  }
                });
              },
        onPanEnd: widget.readOnly
            ? null
            : (details) {
                _finishWireDrawing();
              },
        onPanCancel: widget.readOnly
            ? null
            : () {
                _cancelWireDrawing();
              },
        child: MouseRegion(
          cursor: isHoverInvalid
              ? SystemMouseCursors.forbidden
              : (isHoverValid ? SystemMouseCursors.click : SystemMouseCursors.precise),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: isHovered
                  ? activeColor.withValues(alpha: 0.2)
                  : (isBeingDrawnFrom
                      ? AppColors.primary.withValues(alpha: 0.25)
                      : port.color.withValues(alpha: 0.1)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: activeColor.withValues(alpha: isHovered || isBeingDrawnFrom ? 0.95 : 0.5),
                width: isHovered || isBeingDrawnFrom ? 1.8 : 1.2,
              ),
              boxShadow: (isHovered || isBeingDrawnFrom)
                  ? [
                      BoxShadow(
                        color: activeColor.withValues(alpha: 0.35),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isInput) ...[
                  _buildPortHandle(
                    color: activeColor,
                    isHoverValid: isHoverValid,
                    isHoverInvalid: isHoverInvalid,
                    isActive: isBeingDrawnFrom,
                  ),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                    port.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: activeColor,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!isInput) ...[
                  const SizedBox(width: 5),
                  _buildPortHandle(
                    color: activeColor,
                    isHoverValid: isHoverValid,
                    isHoverInvalid: isHoverInvalid,
                    isActive: isBeingDrawnFrom,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPortHandle({
    required Color color,
    required bool isHoverValid,
    required bool isHoverInvalid,
    required bool isActive,
  }) {
    if (isHoverValid) {
      return Container(
        width: 13,
        height: 13,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.success,
          boxShadow: [
            BoxShadow(
              color: AppColors.success.withValues(alpha: 0.65),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
        child: const Center(
          child: Icon(Icons.check, size: 8.5, color: Colors.white),
        ),
      );
    }
    if (isHoverInvalid) {
      return Container(
        width: 13,
        height: 13,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.danger,
          boxShadow: [
            BoxShadow(
              color: AppColors.danger.withValues(alpha: 0.65),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
        child: const Center(
          child: Icon(Icons.close, size: 8.5, color: Colors.white),
        ),
      );
    }

    // n8n magnetic circular socket pin
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(
          color: isActive ? AppColors.primary : color.withValues(alpha: 0.85),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (isActive ? AppColors.primary : color).withValues(alpha: 0.35),
            blurRadius: 4,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? AppColors.primary : color,
          ),
        ),
      ),
    );
  }

  void _finishWireDrawing() {
    if (_drawingFromNode == null || _drawingFromPort == null || _drawingCurrentPos == null) {
      _cancelWireDrawing();
      return;
    }

    final target = _hoveredTarget;
    final val = _hoveredValidation;

    if (target != null && val != null && val.isValid) {
      final targetNode = target.$1;
      final targetPort = target.$2;

      String fromNodeId;
      String fromPortId;
      String toNodeId;
      String toPortId;

      if (_drawingFromIsInput == false) {
        fromNodeId = _drawingFromNode!.id;
        fromPortId = _drawingFromPort!.id;
        toNodeId = targetNode.id;
        toPortId = targetPort.id;
      } else {
        fromNodeId = targetNode.id;
        fromPortId = targetPort.id;
        toNodeId = _drawingFromNode!.id;
        toPortId = _drawingFromPort!.id;
      }

      // Allow multiple outgoing connections for parallel execution.
      // Only remove if an exact duplicate edge already exists between these two ports.
      widget.graph.edges.removeWhere(
        (e) => e.fromNode == fromNodeId && e.fromPort == fromPortId && e.toNode == toNodeId && e.toPort == toPortId,
      );

      final newEdge = GraphEdge(
        id: 'e_${fromNodeId}_${fromPortId}_${toNodeId}_$toPortId',
        fromNode: fromNodeId,
        fromPort: fromPortId,
        toNode: toNodeId,
        toPort: toPortId,
      );

      setState(() {
        widget.graph.edges.add(newEdge);
        _drawingFromNode = null;
        _drawingFromPort = null;
        _drawingFromIsInput = null;
        _drawingCurrentPos = null;
        _hoveredTarget = null;
        _hoveredValidation = null;
      });
      widget.onGraphChanged();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected $fromNodeId ($fromPortId) → $toNodeId'),
          duration: const Duration(seconds: 2),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (target != null && val != null && !val.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(val.errorMessage ?? 'Connection invalid'),
          duration: const Duration(seconds: 3),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    _cancelWireDrawing();
  }

  void _cancelWireDrawing() {
    setState(() {
      _drawingFromNode = null;
      _drawingFromPort = null;
      _drawingFromIsInput = null;
      _drawingCurrentPos = null;
      _hoveredTarget = null;
      _hoveredValidation = null;
    });
  }
}

/// Route layout metadata for an edge on the graph canvas.
class _EdgeRouteLayout {
  final Offset p1;
  final Offset p2;
  final double corridorOffset;
  final double loopLaneOffset;
  final int totalInSource;
  final int totalInTarget;

  const _EdgeRouteLayout({
    required this.p1,
    required this.p2,
    required this.corridorOffset,
    required this.loopLaneOffset,
    required this.totalInSource,
    required this.totalInTarget,
  });
}

/// Custom Painter for Bézier Edges and In-Progress Cable.
class _EdgesPainter extends CustomPainter {
  _EdgesPainter({
    required this.graph,
    required this.portOffsets,
    required this.edgeLayouts,
    this.selectedEdge,
    this.activeNodeId,
    this.animProgress = 0.0,
    this.isRunning = false,
    this.drawingFromOffset,
    this.drawingCurrentOffset,
    this.drawingFromIsInput = false,
    this.drawingColor = const Color(0xFF4CAF50),
    this.isValidTarget,
  });

  final MissionGraph graph;
  final Map<String, Offset> portOffsets;
  final Map<String, _EdgeRouteLayout> edgeLayouts;
  final GraphEdge? selectedEdge;
  final String? activeNodeId;
  final double animProgress;
  final bool isRunning;
  final Offset? drawingFromOffset;
  final Offset? drawingCurrentOffset;
  final bool drawingFromIsInput;
  final Color drawingColor;
  final bool? isValidTarget;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw saved edges
    for (final edge in graph.edges) {
      final layout = edgeLayouts[edge.id];
      final fromKey = '${edge.fromNode}_out_${edge.fromPort}';
      final toKey = '${edge.toNode}_in_${edge.toPort}';

      final p1 = layout?.p1 ?? (portOffsets[fromKey] ?? _estimateNodePortOffset(edge.fromNode, edge.fromPort, false));
      final p2 = layout?.p2 ?? (portOffsets[toKey] ?? _estimateNodePortOffset(edge.toNode, edge.toPort, true));
      final corridorOffset = layout?.corridorOffset ?? 0.0;
      final loopLaneOffset = layout?.loopLaneOffset ?? 0.0;
      final totalInSource = layout?.totalInSource ?? 1;
      final totalInTarget = layout?.totalInTarget ?? 1;

      final isSelected = selectedEdge?.id == edge.id;
      final isActive = activeNodeId == edge.fromNode;

      Color edgeColor = const Color(0xFF475569);
      final pLow = edge.fromPort.toLowerCase();
      if (pLow == 'failed' || pLow == 'false' || pLow == 'no') {
        edgeColor = AppColors.danger;
      } else if (pLow == 'timeout' || pLow == 'interrupted') {
        edgeColor = AppColors.warning;
      } else if (pLow == 'submitted' || pLow == 'true' || pLow == 'yes' || pLow == 'arrived' || pLow == 'completed' || pLow == 'docked' || pLow == 'undocked' || pLow == 'done' || pLow == 'confirmed' || pLow == 'next') {
        edgeColor = AppColors.success;
      }

      if (isSelected) {
        _drawOrthogonalEdge(
          canvas,
          p1,
          p2,
          AppColors.danger.withValues(alpha: 0.35),
          8.0,
          corridorOffset: corridorOffset,
          loopLaneOffset: loopLaneOffset,
          isSelected: true,
          drawHalo: true,
          isEdgeActive: isActive,
        );
        _drawOrthogonalEdge(
          canvas,
          p1,
          p2,
          AppColors.danger,
          4.0,
          corridorOffset: corridorOffset,
          loopLaneOffset: loopLaneOffset,
          isSelected: true,
          drawHalo: false,
          isEdgeActive: isActive,
        );
      } else {
        _drawOrthogonalEdge(
          canvas,
          p1,
          p2,
          edgeColor,
          isActive ? 4.0 : 3.2,
          corridorOffset: corridorOffset,
          loopLaneOffset: loopLaneOffset,
          isSelected: false,
          drawHalo: true,
          isEdgeActive: isActive,
        );
      }

      // If multiple outgoing edges share this source port, draw a connector pin at p1
      if (totalInSource > 1) {
        final pinHalo = Paint()
          ..color = AppColors.background
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        final pinPaint = Paint()
          ..color = edgeColor
          ..style = PaintingStyle.fill;
        final innerPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        canvas.drawCircle(p1, 5.0, pinHalo);
        canvas.drawCircle(p1, 4.0, pinPaint);
        canvas.drawCircle(p1, 2.0, innerPaint);
      }

      // If multiple incoming edges share this input port, draw a connector pin at p2
      if (totalInTarget > 1) {
        final pinHalo = Paint()
          ..color = AppColors.background
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        final pinPaint = Paint()
          ..color = edgeColor
          ..style = PaintingStyle.fill;
        final innerPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        canvas.drawCircle(p2, 5.5, pinHalo);
        canvas.drawCircle(p2, 4.5, pinPaint);
        canvas.drawCircle(p2, 2.2, innerPaint);
      }
    }

    // 2. Draw live wire in progress
    if (drawingFromOffset != null && drawingCurrentOffset != null) {
      final p1 = drawingFromIsInput ? drawingCurrentOffset! : drawingFromOffset!;
      final p2 = drawingFromIsInput ? drawingFromOffset! : drawingCurrentOffset!;

      Color wireColor = drawingColor.withValues(alpha: 0.9);
      double wireWidth = 2.6;
      bool isDashed = false;

      if (isValidTarget == true) {
        wireColor = AppColors.success;
        wireWidth = 3.6;
      } else if (isValidTarget == false) {
        wireColor = AppColors.danger;
        wireWidth = 2.6;
        isDashed = true;
      }

      if (isDashed) {
        _drawDashedOrthogonalEdge(canvas, p1, p2, wireColor, wireWidth);
      } else {
        _drawOrthogonalEdge(canvas, p1, p2, wireColor, wireWidth);
      }
    }
  }

  Offset _estimateNodePortOffset(String nodeId, String portId, bool isInput) {
    final node = graph.nodes.firstWhere(
      (n) => n.id == nodeId,
      orElse: () => GraphNode(id: '', type: '', position: Offset.zero),
    );
    double y = node.position.dy + 82.0;
    if (isInput) {
      final portIndex = node.inputPorts.indexWhere((p) => p.id == portId);
      if (portIndex > 0) y += portIndex * 26.0;
      return Offset(node.position.dx + 16.0, y);
    } else {
      final portIndex = node.outputPorts.indexWhere((p) => p.id == portId);
      if (portIndex > 0) y += portIndex * 26.0;
      return Offset(node.position.dx + 244.0, y);
    }
  }

  Path _buildOrthogonalPath(
    Offset p1,
    Offset p2, {
    double corridorOffset = 0.0,
    double loopLaneOffset = 0.0,
  }) {
    final points = _MissionGraphCanvasState._getOrthogonalPoints(
      p1,
      p2,
      corridorOffset: corridorOffset,
      loopLaneOffset: loopLaneOffset,
    );
    return _MissionGraphCanvasState._buildSmoothPath(points, 14.0);
  }

  void _drawOrthogonalEdge(
    Canvas canvas,
    Offset p1,
    Offset p2,
    Color color,
    double width, {
    double corridorOffset = 0.0,
    double loopLaneOffset = 0.0,
    bool isSelected = false,
    bool drawHalo = true,
    bool isEdgeActive = false,
  }) {
    final path = _buildOrthogonalPath(
      p1,
      p2,
      corridorOffset: corridorOffset,
      loopLaneOffset: loopLaneOffset,
    );

    // 1. Casing / Halo stroke matching canvas background
    // Creates an automatic visual "bridge" / gap whenever wires cross or overlap,
    // ensuring underlaying wires are NEVER obscured into an indistinguishable mass.
    if (drawHalo) {
      final haloPaint = Paint()
        ..color = AppColors.background
        ..strokeWidth = width + 4.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, haloPaint);

      // 2. Subtle drop shadow
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: isSelected ? 0.22 : 0.08)
        ..strokeWidth = width + 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, shadowPaint);
    }

    // 3. Main colored edge wire
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);

    // 4. Directional arrowheads & Traveling energy particles
    final metrics = path.computeMetrics().toList();
    if (metrics.isNotEmpty) {
      final metric = metrics.first;
      final totalLen = metric.length;

      // Primary: Destination Entry Arrowhead
      // Placed right before destination port entering horizontally from the left.
      // At this location (metric.length - 12.0), the wire is strictly traveling
      // forward (+X) into the input pin. This arrowhead is ALWAYS pointing forward (> [Port]),
      // eliminating any reverse or backwards pointing arrows!
      if (totalLen >= 18.0) {
        final endOffset = math.max(4.0, totalLen - 12.0);
        final endTangent = metric.getTangentForOffset(endOffset);
        if (endTangent != null) {
          final arrowSize = math.max(width * 2.6, 9.5);
          _drawArrowHead(canvas, endTangent.position, endTangent.angle, color, arrowSize);
        }
      }

      // Secondary: Mid-span directional arrow (for long forward wires only)
      // Only draw mid-arrow if the path is sufficiently long, forward-directed (p2.dx >= p1.dx + 60.0),
      // and the tangent vector is pointing strictly in the forward (+X) direction (> 0.3).
      // NEVER draw mid-arrows on reverse loopback bridges where tangent dx is negative!
      if (totalLen > 180.0 && p2.dx >= p1.dx + 60.0) {
        final midTangent = metric.getTangentForOffset(totalLen * 0.5);
        if (midTangent != null && midTangent.vector.dx > 0.3) {
          final midArrowSize = math.max(width * 2.3, 8.5);
          _drawArrowHead(canvas, midTangent.position, midTangent.angle, color, midArrowSize);
        }
      }

      // 5. Traveling energy particles (signature n8n flow animation)
      final shouldAnimateFlow = isRunning || isEdgeActive || isSelected;
      if (shouldAnimateFlow && totalLen > 24.0) {
        final particleCount = totalLen > 360.0 ? 3 : (totalLen > 140.0 ? 2 : 1);
        final speedMultiplier = isEdgeActive ? 1.0 : (isSelected ? 0.75 : 0.5);

        for (int p = 0; p < particleCount; p++) {
          final t = ((animProgress * speedMultiplier + (p / particleCount)) % 1.0);
          final offset = totalLen * t;
          final tangent = metric.getTangentForOffset(offset);
          if (tangent != null) {
            // Glowing wake / tail trailing behind the bead along the wire
            final tailLen = math.min(22.0, offset);
            if (tailLen > 4.0) {
              final tailPath = metric.extractPath(offset - tailLen, offset);
              final tailPaint = Paint()
                ..color = color.withValues(alpha: isEdgeActive ? 0.65 : 0.35)
                ..strokeWidth = (isEdgeActive ? 4.5 : 3.2) + 0.8
                ..style = PaintingStyle.stroke
                ..strokeCap = StrokeCap.round;
              canvas.drawPath(tailPath, tailPaint);
            }

            // Soft glowing aura around bead
            final auraPaint = Paint()
              ..color = (isEdgeActive ? Colors.white : color).withValues(alpha: isEdgeActive ? 0.6 : 0.4)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5);
            canvas.drawCircle(tangent.position, isEdgeActive ? 5.5 : 4.5, auraPaint);

            // Crisp bright white bead core
            final corePaint = Paint()
              ..color = Colors.white
              ..style = PaintingStyle.fill;
            canvas.drawCircle(tangent.position, isEdgeActive ? 2.8 : 2.2, corePaint);
          }
        }
      }
    }
  }

  void _drawArrowHead(Canvas canvas, Offset pos, double angle, Color color, double arrowSize) {
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Halo casing border on arrowhead to prevent blending with background or crossing lines
    final haloBorderPaint = Paint()
      ..color = AppColors.background
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(angle);

    final arrowPath = Path()
      ..moveTo(arrowSize * 0.45, 0)
      ..lineTo(-arrowSize * 0.45, -arrowSize * 0.4)
      ..lineTo(-arrowSize * 0.18, 0)
      ..lineTo(-arrowSize * 0.45, arrowSize * 0.4)
      ..close();

    canvas.drawPath(arrowPath, haloBorderPaint);
    canvas.drawPath(arrowPath, arrowPaint);
    canvas.restore();
  }

  void _drawDashedOrthogonalEdge(
    Canvas canvas,
    Offset p1,
    Offset p2,
    Color color,
    double width, {
    double corridorOffset = 0.0,
    double loopLaneOffset = 0.0,
  }) {
    final path = _buildOrthogonalPath(
      p1,
      p2,
      corridorOffset: corridorOffset,
      loopLaneOffset: loopLaneOffset,
    );

    final haloPaint = Paint()
      ..color = AppColors.background
      ..strokeWidth = width + 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, haloPaint);

    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final len = math.min(8.0, metric.length - distance);
        final extract = metric.extractPath(distance, distance + len);
        canvas.drawPath(extract, paint);
        distance += len + 6.0;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EdgesPainter oldDelegate) => true;
}

/// Subtle Dot Grid Background Painter matching light engineering canvas.
class _GridBackgroundPainter extends CustomPainter {
  const _GridBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = const Color(0xFFCBD5E1).withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    const double spacing = 28.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.15, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
