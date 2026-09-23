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

      final localAnchor = Offset(
        portBox.size.width / 2.0,
        portBox.size.height / 2.0,
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

  static bool _isTerminalBadge(GraphNode node) =>
      node.type == 'end' || node.type == 'mission_end' || node.type == 'dock_and_end';

  static double _getNodeWidth(GraphNode node) {
    if (_isTerminalBadge(node)) {
      return 56.0;
    }
    final labelLen = (node.label.isNotEmpty ? node.label : node.type).length;
    final textWidth = (labelLen * 7.5).clamp(80.0, 160.0);

    if (node.outputPorts.length > 1) {
      int maxPortLen = 0;
      for (final p in node.outputPorts) {
        if (p.label.length > maxPortLen) maxPortLen = p.label.length;
      }
      final portColumnWidth = (maxPortLen * 6.8 + 16.0).clamp(48.0, 110.0);
      return math.max(250.0, 72.0 + textWidth + portColumnWidth + 24.0);
    }
    return math.max(230.0, 75.0 + textWidth + 30.0);
  }

  static double _getNodeHeight(GraphNode node) {
    if (_isTerminalBadge(node)) {
      return 56.0;
    }
    final outCount = node.outputPorts.length;
    if (outCount <= 1) return 66.0;
    if (outCount == 2) return 82.0;
    return 66.0 + (outCount - 1) * 28.0;
  }

  static double _getPortY(GraphNode node, int index, bool isInput) {
    final nodeHeight = _getNodeHeight(node);
    if (isInput) {
      return nodeHeight / 2.0;
    }
    final outCount = node.outputPorts.length;
    if (outCount <= 1) {
      return nodeHeight / 2.0;
    }
    const topPad = 20.0;
    final available = nodeHeight - 2 * topPad;
    final step = available / (outCount - 1);
    return topPad + index * step;
  }

  static Offset _estimatePortOffsetStatic(GraphNode node, String portId, bool isInput) {
    final nodeWidth = _getNodeWidth(node);
    final nodeHeight = _getNodeHeight(node);
    if (isInput) {
      return Offset(node.position.dx, node.position.dy + nodeHeight / 2.0);
    } else {
      final idx = node.outputPorts.indexWhere((p) => p.id == portId);
      final pinY = _getPortY(node, idx >= 0 ? idx : 0, false);
      return Offset(node.position.dx + nodeWidth, node.position.dy + pinY);
    }
  }

  static Color _getPortColor(NodePort port, bool isInput) {
    if (isInput) return const Color(0xFF0284C7); // Sky Blue
    final id = port.id.toLowerCase();
    if (id == 'true' || id == 'arrived' || id == 'docked' || id == 'undocked' || id == 'completed' || id == 'ok' || id == 'submitted' || id == 'next' || id == 'yes') {
      return const Color(0xFF10B981); // Emerald Green
    }
    if (id == 'false' || id == 'failed' || id == 'low_battery' || id == 'cancelled' || id == 'no' || id == 'abort') {
      return const Color(0xFFEF4444); // Red
    }
    if (id == 'timeout' || id == 'interrupted' || id == 'warning') {
      return const Color(0xFFF59E0B); // Amber / Orange
    }
    if (id == 'loop_body' || id.startsWith('branch_')) {
      return const Color(0xFF8B5CF6); // Purple
    }
    return port.color;
  }

  Offset _estimatePortOffset(GraphNode node, String portId, bool isInput) {
    return _estimatePortOffsetStatic(node, portId, isInput);
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
      final nodeWidth = _getNodeWidth(node);
      final nodeHeight = _getNodeHeight(node);
      final nodeRect = Rect.fromLTWH(node.position.dx - 12, node.position.dy - 6, nodeWidth + 24, nodeHeight + 12);
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

  static Path _buildBezierPath(
    Offset p1,
    Offset p2, {
    double corridorOffset = 0.0,
    double loopLaneOffset = 0.0,
  }) {
    final path = Path();
    path.moveTo(p1.dx, p1.dy);

    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;

    if (dx >= 20.0) {
      // Forward horizontal cubic Bézier curve
      final curvature = math.max(dx * 0.45, 45.0);
      final cp1 = Offset(p1.dx + curvature, p1.dy + corridorOffset);
      final cp2 = Offset(p2.dx - curvature, p2.dy + corridorOffset);
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    } else {
      // Reverse / loopback edge
      final loopOut = math.max(55.0, (p1.dx - p2.dx) * 0.28);
      final midX = (p1.dx + p2.dx) / 2.0;
      final arcHeight = (dy < 0 ? -75.0 : 75.0) + loopLaneOffset;
      final midY = (p1.dy + p2.dy) / 2.0 + arcHeight;

      path.cubicTo(
        p1.dx + loopOut, p1.dy,
        midX + loopOut, midY,
        midX, midY,
      );
      path.cubicTo(
        midX - loopOut, midY,
        p2.dx - loopOut, p2.dy,
        p2.dx, p2.dy,
      );
    }

    return path;
  }

  static bool _isPointNearBezier(
    Offset pt,
    Offset p1,
    Offset p2,
    double threshold, {
    double corridorOffset = 0.0,
    double loopLaneOffset = 0.0,
  }) {
    final path = _buildBezierPath(
      p1,
      p2,
      corridorOffset: corridorOffset,
      loopLaneOffset: loopLaneOffset,
    );
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return false;
    final metric = metrics.first;
    final totalLen = metric.length;
    if (totalLen <= 0) return false;

    final steps = math.max(12, (totalLen / 16.0).round());
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final pos = metric.getTangentForOffset(t * totalLen)?.position;
      if (pos != null && (pos - pt).distance <= threshold) {
        return true;
      }
    }
    return false;
  }

  static Offset _getBezierMidpoint(
    Offset p1,
    Offset p2, {
    double corridorOffset = 0.0,
    double loopLaneOffset = 0.0,
  }) {
    final path = _buildBezierPath(
      p1,
      p2,
      corridorOffset: corridorOffset,
      loopLaneOffset: loopLaneOffset,
    );
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return (p1 + p2) / 2.0;
    final metric = metrics.first;
    return metric.getTangentForOffset(metric.length * 0.5)?.position ?? (p1 + p2) / 2.0;
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

      // Connect all incoming lines directly to the EXACT same input socket point (baseP2)
      // and outgoing lines directly to the output socket point (baseP1)
      final p1 = baseP1;
      final p2 = baseP2;
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
    final mid = _getBezierMidpoint(
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
                  if (_isPointNearBezier(
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
                              selectedNodeId: widget.selectedNode?.id,
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

    if (_isTerminalBadge(node)) {
      if (isActive) {
        return AnimatedBuilder(
          animation: _flowAnimController,
          builder: (context, _) {
            final pulse = (math.sin(_flowAnimController.value * 2 * math.pi) + 1.0) / 2.0;
            return _buildTerminalBadgeWidget(
              node,
              isSelected: isSelected,
              isActive: true,
              pulse: pulse,
            );
          },
        );
      }
      return _buildTerminalBadgeWidget(
        node,
        isSelected: isSelected,
        isActive: false,
        pulse: 0.0,
      );
    }

    final double nodeWidth = _getNodeWidth(node);
    final double nodeHeight = _getNodeHeight(node);

    return Positioned(
      left: node.position.dx,
      top: node.position.dy,
      child: SizedBox(
        width: nodeWidth,
        height: nodeHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 1. Sleek n8n Node Tile
            if (isActive)
              AnimatedBuilder(
                animation: _flowAnimController,
                builder: (context, _) {
                  final pulse = (math.sin(_flowAnimController.value * 2 * math.pi) + 1.0) / 2.0;
                  return _buildNodeCard(
                    node,
                    isSelected: isSelected,
                    isActive: true,
                    pulse: pulse,
                    nodeWidth: nodeWidth,
                    nodeHeight: nodeHeight,
                  );
                },
              )
            else
              _buildNodeCard(
                node,
                isSelected: isSelected,
                isActive: false,
                pulse: 0.0,
                nodeWidth: nodeWidth,
                nodeHeight: nodeHeight,
              ),

            // 2. Magnetic Outer Input Pin on Left Border
            if (node.inputPorts.isNotEmpty)
              Positioned(
                left: -9.0,
                top: (nodeHeight - 18.0) / 2.0,
                child: _buildPortPin(
                  node: node,
                  port: node.inputPorts.first,
                  isInput: true,
                ),
              ),

            // 3. Magnetic Outer Output Pin(s) on Right Border
            for (int i = 0; i < node.outputPorts.length; i++)
              Positioned(
                right: -9.0,
                top: _getPortY(node, i, false) - 9.0,
                child: _buildPortPin(
                  node: node,
                  port: node.outputPorts[i],
                  isInput: false,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTerminalBadgeWidget(
    GraphNode node, {
    required bool isSelected,
    required bool isActive,
    required double pulse,
  }) {
    const double badgeSize = 56.0;
    const double totalHeight = 76.0;

    final dockOnEnd = node.type == 'dock_and_end' || node.params['dock_on_end'] == true;
    final status = (node.params['status'] as String? ?? 'success').toLowerCase();
    final isAborted = status == 'failed' || status == 'aborted';

    final Color badgeColor = isAborted
        ? const Color(0xFFEF4444)
        : (dockOnEnd ? const Color(0xFF10B981) : const Color(0xFF0D9488));

    final IconData badgeIcon = isAborted
        ? Icons.stop_rounded
        : (dockOnEnd ? Icons.battery_charging_full_rounded : Icons.flag_rounded);

    final String badgeLabel = isAborted
        ? 'ABORT'
        : (dockOnEnd ? 'DOCK & END' : 'FINISH');

    final glowAlpha = 0.25 + 0.35 * pulse;
    final glowBlur = 12.0 + 8.0 * pulse;

    return Positioned(
      left: node.position.dx,
      top: node.position.dy,
      child: SizedBox(
        width: badgeSize,
        height: totalHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Circular Badge Sunk Button
            GestureDetector(
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
                      });
                      widget.onGraphChanged();
                    },
              onTap: () {
                widget.onSelectNode(node);
                _setSelectedEdge(null);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: badgeSize,
                    height: badgeSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surface,
                      border: Border.all(
                        color: isActive
                            ? Color.lerp(AppColors.primary, AppColors.primaryLight, pulse)!
                            : isSelected
                                ? AppColors.primary
                                : badgeColor,
                        width: isSelected || isActive ? 2.6 : 2.0,
                      ),
                      boxShadow: [
                        if (isActive)
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: glowAlpha),
                            blurRadius: glowBlur,
                            spreadRadius: 2.0 * pulse,
                          )
                        else if (isSelected)
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 2),
                          )
                        else
                          BoxShadow(
                            color: badgeColor.withValues(alpha: 0.18),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                      ],
                    ),
                    child: Center(
                      child: Icon(badgeIcon, size: 28, color: badgeColor),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: badgeColor.withValues(alpha: 0.35),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      badgeLabel,
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: badgeColor,
                        letterSpacing: 0.4,
                      ),
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),

            // Left Outer Input Socket Pin
            if (node.inputPorts.isNotEmpty)
              Positioned(
                left: -9.0,
                top: (badgeSize - 18.0) / 2.0,
                child: _buildPortPin(
                  node: node,
                  port: node.inputPorts.first,
                  isInput: true,
                ),
              ),

            // Delete (x) button on hover/top right
            if (!widget.readOnly)
              Positioned(
                top: -3,
                right: -3,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      widget.graph.nodes.remove(node);
                      widget.graph.edges.removeWhere(
                          (e) => e.fromNode == node.id || e.toNode == node.id);
                      if (widget.selectedNode?.id == node.id) {
                        widget.onSelectNode(null);
                      }
                    });
                    widget.onGraphChanged();
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surface,
                      border: Border.all(color: AppColors.border),
                    ),
                    padding: const EdgeInsets.all(2.5),
                    child: const Icon(Icons.close_rounded, size: 11, color: AppColors.textTertiary),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNodeCard(
    GraphNode node, {
    required bool isSelected,
    required bool isActive,
    required double pulse,
    required double nodeWidth,
    required double nodeHeight,
  }) {
    final glowAlpha = 0.25 + 0.35 * pulse;
    final glowBlur = 12.0 + 8.0 * pulse;
    final glowSpread = 1.0 + 2.0 * pulse;

    final (categoryTitle, icon, categoryColor) = _getNodeCategoryMeta(node.type);
    final subtitle = _getNodeShortSummary(node);
    final hasMultipleOutputs = node.outputPorts.length > 1;

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
        height: nodeHeight,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? Color.lerp(AppColors.primary, AppColors.primaryLight, pulse)!
                : isSelected
                    ? AppColors.primary
                    : AppColors.border,
            width: isActive ? 2.2 : isSelected ? 2.0 : 1.2,
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
        child: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Squircle Category Icon Box
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: categoryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: categoryColor.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Icon(icon, size: 19, color: categoryColor),
                  ),
                ),
                const SizedBox(width: 9),
                // Center Column: Category tag, Node title, 1-line parameter summary
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        categoryTitle.toUpperCase(),
                        style: TextStyle(
                          color: categoryColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
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
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 1.5),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),

                // Dedicated Right Column for Branching Output Port Labels (cleanly separated, no overlap!)
                if (hasMultipleOutputs) ...[
                  const SizedBox(width: 6),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final port in node.outputPorts)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: _getPortColor(port, false).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: _getPortColor(port, false).withValues(alpha: 0.35),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            port.label,
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700,
                              color: _getPortColor(port, false),
                            ),
                            maxLines: 1,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 2),
                ],
              ],
            ),

            // Running Status Badge
            if (isActive && widget.isRunning)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.success,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.success.withValues(alpha: 0.8),
                        blurRadius: 4 + 3 * pulse,
                      ),
                    ],
                  ),
                ),
              )
            else if (!widget.readOnly && node.type != 'start')
              Positioned(
                top: -2,
                right: -2,
                child: InkWell(
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
                  borderRadius: BorderRadius.circular(10),
                  child: const Padding(
                    padding: EdgeInsets.all(3.0),
                    child: Icon(Icons.close_rounded, size: 13, color: AppColors.textTertiary),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortPin({
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

    Color activeColor = _getPortColor(port, isInput);
    if (isHoverValid) {
      activeColor = AppColors.success;
    } else if (isHoverInvalid) {
      activeColor = AppColors.danger;
    } else if (isBeingDrawnFrom) {
      activeColor = AppColors.primary;
    }

    const double baseSize = 18.0;
    final pinSize = (isHovered || isBeingDrawnFrom) ? 22.0 : baseSize;

    return KeyedSubtree(
      key: gKey,
      child: Tooltip(
        message: port.label,
        waitDuration: const Duration(milliseconds: 200),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
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
              width: pinSize,
              height: pinSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surface,
                border: Border.all(
                  color: activeColor,
                  width: (isHovered || isBeingDrawnFrom) ? 2.6 : 2.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isHovered || isBeingDrawnFrom)
                        ? activeColor.withValues(alpha: 0.5)
                        : activeColor.withValues(alpha: 0.25),
                    blurRadius: (isHovered || isBeingDrawnFrom) ? 8 : 4,
                    spreadRadius: (isHovered || isBeingDrawnFrom) ? 1.5 : 0.5,
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: (isHovered || isBeingDrawnFrom) ? 9.0 : 7.0,
                  height: (isHovered || isBeingDrawnFrom) ? 9.0 : 7.0,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: activeColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  (String, IconData, Color) _getNodeCategoryMeta(String type) {
    switch (type) {
      case 'start':
        return ('Trigger', Icons.bolt_rounded, AppColors.success);
      case 'end':
      case 'mission_end':
      case 'dock_and_end':
        return ('Terminal', Icons.battery_charging_full_rounded, const Color(0xFF10B981));
      case 'navigate_waypoint':
        return ('Navigation', Icons.navigation_rounded, const Color(0xFF2563EB));
      case 'navigate_coordinates':
        return ('Coordinates', Icons.explore_rounded, const Color(0xFF2563EB));
      case 'patrol_loop':
        return ('Patrol Loop', Icons.sync_rounded, const Color(0xFF3B82F6));
      case 'relocalize':
        return ('Localization', Icons.my_location_rounded, const Color(0xFF0284C7));
      case 'cancel_navigation':
        return ('Navigation', Icons.cancel_rounded, const Color(0xFFDC2626));
      case 'wait':
        return ('Timing', Icons.timer_outlined, AppColors.warning);
      case 'dock':
        return ('Power & Dock', Icons.battery_charging_full_rounded, const Color(0xFF16A34A));
      case 'undock':
        return ('Power & Dock', Icons.power_settings_new_rounded, const Color(0xFF059669));
      case 'jog_motion':
        return ('Actuator', Icons.gamepad_outlined, const Color(0xFFD97706));
      case 'emergency_stop':
        return ('Safety', Icons.emergency_rounded, const Color(0xFFDC2626));
      case 'loop':
      case 'loop_counter':
        return ('Logic Flow', Icons.loop_rounded, const Color(0xFF7C3AED));
      case 'condition':
        return ('Branch Logic', Icons.call_split_rounded, const Color(0xFFEA580C));
      case 'parallel':
      case 'parallel_fork':
        return ('Parallel Flow', Icons.alt_route_rounded, const Color(0xFF00ACC1));
      case 'battery_guard':
        return ('Safety Guard', Icons.battery_saver_rounded, const Color(0xFF059669));
      case 'set_variable':
        return ('Variables', Icons.data_object_rounded, const Color(0xFF9333EA));
      case 'ui_interaction':
        return ('Kiosk Form', Icons.touch_app_rounded, AppColors.primary);
      case 'ui_notification':
        return ('Kiosk Alert', Icons.notifications_active_rounded, const Color(0xFF0284C7));
      case 'ui_choice':
        return ('Kiosk Dialog', Icons.ads_click_rounded, AppColors.primary);
      case 'ui_media':
        return ('Kiosk Media', Icons.smart_display_rounded, const Color(0xFF0284C7));
      case 'ui_speech':
        return ('Voice TTS', Icons.record_voice_over_rounded, const Color(0xFF8B5CF6));
      case 'notify':
        return ('Robot Signal', Icons.lightbulb_rounded, const Color(0xFF0D9488));
      case 'call_api':
        return ('Webhook & API', Icons.http_rounded, const Color(0xFF7C3AED));
      case 'call_service':
        return ('ROS 2 Service', Icons.precision_manufacturing_rounded, const Color(0xFF4F46E5));
      case 'call_action':
        return ('ROS 2 Action', Icons.settings_input_component_rounded, const Color(0xFF4F46E5));
      case 'publish_topic':
        return ('ROS 2 Topic', Icons.podcasts_rounded, const Color(0xFF4F46E5));
      case 'switch_mission':
      case 'redirect_mission':
        return ('Workflow', Icons.shuffle_rounded, const Color(0xFF009688));
      default:
        return ('Step', Icons.circle_outlined, AppColors.textSecondary);
    }
  }

  String _getNodeShortSummary(GraphNode node) {
    switch (node.type) {
      case 'start':
        final trigger = node.params['trigger'] as String? ?? 'manual';
        if (trigger == 'interval') {
          final mins = (node.params['interval_minutes'] as num?)?.toInt() ?? 30;
          return 'Every ${mins}m';
        } else if (trigger == 'schedule') {
          final hour = (node.params['schedule_hour'] as num?)?.toInt() ?? 9;
          final min = (node.params['schedule_minute'] as num?)?.toInt() ?? 0;
          final rep = node.params['schedule_type'] as String? ?? 'daily';
          final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
          final amPm = hour >= 12 ? 'PM' : 'AM';
          return '$rep at $h12:${min.toString().padLeft(2, '0')} $amPm';
        }
        return 'Manual start';
      case 'end':
      case 'mission_end':
      case 'dock_and_end':
        return (node.type == 'dock_and_end' || node.params['dock_on_end'] == true) ? 'Finish & Dock' : 'Finish';
      case 'navigate_waypoint':
        final wp = node.params['waypoint']?.toString() ?? '';
        return wp.isNotEmpty ? wp : 'Set destination';
      case 'navigate_coordinates':
        return 'X: ${node.params['x'] ?? 0}, Y: ${node.params['y'] ?? 0}';
      case 'patrol_loop':
        final wps = (node.params['waypoints'] as List?)?.length ?? 0;
        final laps = node.params['laps'] ?? 1;
        return '$wps points · $laps laps';
      case 'relocalize':
        return 'Scan room';
      case 'cancel_navigation':
        return 'Halt robot';
      case 'wait':
        final sec = node.params['duration_sec'] ?? node.params['duration'] ?? 5;
        return '${sec}s delay';
      case 'dock':
        return 'Auto-dock';
      case 'undock':
        return 'Leave dock';
      case 'jog_motion':
        final dur = node.params['duration_sec'] ?? 1.0;
        return '${dur}s move';
      case 'emergency_stop':
        return 'Motor cut';
      case 'loop':
      case 'loop_counter':
        final count = node.params['count'] ?? 3;
        return 'Repeat ${count}x';
      case 'condition':
        final expr = node.params['expression'] ?? '';
        return expr.isNotEmpty ? 'if: $expr' : 'Conditional';
      case 'battery_guard':
        final minB = node.params['min_battery_pct'] ?? 20;
        return 'Min: $minB%';
      case 'set_variable':
        final varName = node.params['variable_name'] ?? 'var';
        final val = node.params['value'] ?? '';
        return '$varName = $val';
      case 'call_api':
        final method = node.params['method'] ?? 'POST';
        final url = node.params['url']?.toString() ?? '';
        return url.isNotEmpty ? '$method $url' : '$method request';
      case 'call_service':
        final srv = node.params['service_name']?.toString() ?? '';
        return srv.isNotEmpty ? srv : 'ROS 2 service';
      case 'call_action':
        final act = node.params['action_name']?.toString() ?? '';
        return act.isNotEmpty ? act : 'ROS 2 action';
      case 'publish_topic':
        final top = node.params['topic_name']?.toString() ?? '';
        return top.isNotEmpty ? top : 'ROS 2 topic';
      case 'ui_interaction':
        return node.params['title']?.toString() ?? 'Touch form';
      case 'ui_choice':
        return node.params['title']?.toString() ?? 'User choice';
      case 'ui_notification':
        return node.params['title']?.toString() ?? 'Notice';
      case 'ui_media':
        return node.params['media_type']?.toString() ?? 'Media display';
      case 'ui_speech':
        final text = node.params['text']?.toString() ?? '';
        return text.isNotEmpty ? '"$text"' : 'Voice speak';
      case 'notify':
        return node.params['oled_text']?.toString() ?? 'Chime & LEDs';
      case 'switch_mission':
      case 'redirect_mission':
        final target = (node.params['target_mission_id'] ?? node.params['mission_id'])?.toString() ?? '';
        return target.isNotEmpty ? 'Switch: $target' : 'Switch mission';
      default:
        return '';
    }
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
    this.selectedNodeId,
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
  final String? selectedNodeId;
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

      final isEdgeSelected = selectedEdge?.id == edge.id;
      final isConnectedToSelectedNode = selectedNodeId != null &&
          (selectedNodeId == edge.fromNode || selectedNodeId == edge.toNode);
      final isActive = activeNodeId == edge.fromNode || (activeNodeId != null && activeNodeId == edge.toNode);

      Color edgeColor = const Color(0xFF475569);
      final pLow = edge.fromPort.toLowerCase();
      if (pLow == 'failed' || pLow == 'false' || pLow == 'no' || pLow == 'low_battery' || pLow == 'cancelled' || pLow == 'abort') {
        edgeColor = AppColors.danger;
      } else if (pLow == 'timeout' || pLow == 'interrupted' || pLow == 'warning') {
        edgeColor = AppColors.warning;
      } else if (pLow == 'submitted' || pLow == 'true' || pLow == 'yes' || pLow == 'arrived' || pLow == 'completed' || pLow == 'docked' || pLow == 'undocked' || pLow == 'done' || pLow == 'confirmed' || pLow == 'next' || pLow == 'ok') {
        edgeColor = AppColors.success;
      }

      if (isEdgeSelected) {
        _drawBezierEdge(
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
        _drawBezierEdge(
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
      } else if (isConnectedToSelectedNode || isActive) {
        // Highlighted solid wire with glowing halo and energy particles for connected selected node or active step
        _drawBezierEdge(
          canvas,
          p1,
          p2,
          edgeColor,
          isActive ? 4.0 : 3.4,
          corridorOffset: corridorOffset,
          loopLaneOffset: loopLaneOffset,
          isSelected: true,
          drawHalo: true,
          isEdgeActive: true,
        );
      } else {
        // Default unselected: clean subtle dotted/dashed Bézier wire with directional arrowhead!
        _drawDashedBezierEdge(
          canvas,
          p1,
          p2,
          edgeColor.withValues(alpha: 0.65),
          2.0,
          corridorOffset: corridorOffset,
          loopLaneOffset: loopLaneOffset,
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
        _drawDashedBezierEdge(canvas, p1, p2, wireColor, wireWidth);
      } else {
        _drawBezierEdge(canvas, p1, p2, wireColor, wireWidth);
      }
    }
  }

  Offset _estimateNodePortOffset(String nodeId, String portId, bool isInput) {
    final node = graph.nodes.firstWhere(
      (n) => n.id == nodeId,
      orElse: () => GraphNode(id: '', type: '', position: Offset.zero),
    );
    return _MissionGraphCanvasState._estimatePortOffsetStatic(node, portId, isInput);
  }

  Path _buildBezierPath(
    Offset p1,
    Offset p2, {
    double corridorOffset = 0.0,
    double loopLaneOffset = 0.0,
  }) {
    return _MissionGraphCanvasState._buildBezierPath(
      p1,
      p2,
      corridorOffset: corridorOffset,
      loopLaneOffset: loopLaneOffset,
    );
  }

  void _drawBezierEdge(
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
    final path = _buildBezierPath(
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

      // Primary: Destination Entry Arrowhead right before destination port
      if (totalLen >= 18.0) {
        final endOffset = math.max(4.0, totalLen - 12.0);
        final endTangent = metric.getTangentForOffset(endOffset);
        if (endTangent != null) {
          final arrowSize = math.max(width * 2.6, 9.5);
          _drawArrowHead(canvas, endTangent.position, endTangent.angle, color, arrowSize);
        }
      }

      // Secondary: Mid-span directional arrow (for long forward wires only)
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

  void _drawDashedBezierEdge(
    Canvas canvas,
    Offset p1,
    Offset p2,
    Color color,
    double width, {
    double corridorOffset = 0.0,
    double loopLaneOffset = 0.0,
  }) {
    final path = _buildBezierPath(
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

    final metrics = path.computeMetrics().toList();
    for (final metric in metrics) {
      double distance = 0.0;
      while (distance < metric.length) {
        final len = math.min(7.0, metric.length - distance);
        final extract = metric.extractPath(distance, distance + len);
        canvas.drawPath(extract, paint);
        distance += len + 5.0;
      }
    }

    if (metrics.isNotEmpty) {
      final metric = metrics.first;
      final totalLen = metric.length;
      if (totalLen >= 18.0) {
        final endOffset = math.max(4.0, totalLen - 12.0);
        final endTangent = metric.getTangentForOffset(endOffset);
        if (endTangent != null) {
          final arrowSize = math.max(width * 2.5, 9.0);
          _drawArrowHead(canvas, endTangent.position, endTangent.angle, color, arrowSize);
        }
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
