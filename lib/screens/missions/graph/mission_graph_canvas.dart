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
    this.activeNodeId,
    this.readOnly = false,
    this.isRunning = false,
  });

  final MissionGraph graph;
  final GraphNode? selectedNode;
  final ValueChanged<GraphNode?> onSelectNode;
  final VoidCallback onGraphChanged;
  final String? activeNodeId;
  final bool readOnly;
  final bool isRunning;

  @override
  State<MissionGraphCanvas> createState() => _MissionGraphCanvasState();
}

class _MissionGraphCanvasState extends State<MissionGraphCanvas> {
  final TransformationController _transformController = TransformationController();
  final GlobalKey _canvasKey = GlobalKey();

  // Wire drawing state
  GraphNode? _drawingFromNode;
  NodePort? _drawingFromPort;
  bool? _drawingFromIsInput;
  Offset? _drawingCurrentPos;

  // Selected edge for deletion
  GraphEdge? _selectedEdge;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _updatePortOffsets());
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

  bool _isPointNearBezier(Offset pt, Offset p1, Offset p2, double threshold) {
    final rect = Rect.fromPoints(p1, p2).inflate(threshold + 20);
    if (!rect.contains(pt)) return false;

    final dx = (p2.dx - p1.dx).abs() * 0.5;
    final cp1 = Offset(p1.dx + math.max(dx, 40), p1.dy);
    final cp2 = Offset(p2.dx - math.max(dx, 40), p2.dy);

    for (int i = 0; i <= 20; i++) {
      final t = i / 20.0;
      final u = 1.0 - t;
      final x = u * u * u * p1.dx +
          3 * u * u * t * cp1.dx +
          3 * u * t * t * cp2.dx +
          t * t * t * p2.dx;
      final y = u * u * u * p1.dy +
          3 * u * u * t * cp1.dy +
          3 * u * t * t * cp2.dy +
          t * t * t * p2.dy;
      if ((Offset(x, y) - pt).distanceSquared <= threshold * threshold) {
        return true;
      }
    }
    return false;
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
              onTap: () {
                setState(() {
                  _selectedEdge = null;
                });
                widget.onSelectNode(null);
              },
              onTapUp: (details) {
                final tapPos = details.localPosition;
                GraphEdge? clickedEdge;
                for (final edge in widget.graph.edges) {
                  final fromKey = '${edge.fromNode}_out_${edge.fromPort}';
                  final toKey = '${edge.toNode}_in_${edge.toPort}';
                  final fromNode = widget.graph.nodes.firstWhere((n) => n.id == edge.fromNode, orElse: () => GraphNode(id: '', type: '', position: Offset.zero));
                  final toNode = widget.graph.nodes.firstWhere((n) => n.id == edge.toNode, orElse: () => GraphNode(id: '', type: '', position: Offset.zero));
                  final p1 = _portOffsets[fromKey] ?? _estimatePortOffset(fromNode, edge.fromPort, false);
                  final p2 = _portOffsets[toKey] ?? _estimatePortOffset(toNode, edge.toPort, true);
                  if (_isPointNearBezier(tapPos, p1, p2, 16.0)) {
                    clickedEdge = edge;
                    break;
                  }
                }
                if (clickedEdge != null) {
                  setState(() {
                    _selectedEdge = clickedEdge;
                  });
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
                      child: CustomPaint(
                        painter: _EdgesPainter(
                          graph: widget.graph,
                          portOffsets: _portOffsets,
                          selectedEdge: _selectedEdge,
                          activeNodeId: widget.activeNodeId,
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
                      ),
                    ),

                    // Node Widgets
                    for (final node in widget.graph.nodes)
                      _buildNodeWidget(node),
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
                          setState(() {
                            widget.graph.edges.remove(_selectedEdge);
                            _selectedEdge = null;
                          });
                          widget.onGraphChanged();
                        },
                        icon: const Icon(Icons.delete_outline, size: 14),
                        label: const Text('Delete Edge'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
                        onPressed: () => setState(() => _selectedEdge = null),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Canvas Controls (Zoom In, Zoom Out, Reset)
          Positioned(
            bottom: 16,
            right: 16,
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
                    icon: const Icon(Icons.add, color: AppColors.textPrimary),
                    tooltip: 'Zoom In',
                    onPressed: () {
                      final matrix = _transformController.value.clone();
                      matrix.scaleByDouble(1.2, 1.2, 1.0, 1.0);
                      _transformController.value = matrix;
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove, color: AppColors.textPrimary),
                    tooltip: 'Zoom Out',
                    onPressed: () {
                      final matrix = _transformController.value.clone();
                      matrix.scaleByDouble(0.8, 0.8, 1.0, 1.0);
                      _transformController.value = matrix;
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.center_focus_strong, color: AppColors.textPrimary),
                    tooltip: 'Reset View',
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
    const double nodeWidth = 240.0;

    return Positioned(
      left: node.position.dx,
      top: node.position.dy,
      child: GestureDetector(
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
          setState(() {
            _selectedEdge = null;
          });
        },
        child: Container(
          width: nodeWidth,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActive
                  ? AppColors.primary
                  : isSelected
                      ? AppColors.primary
                      : AppColors.border,
              width: isActive ? 2.5 : isSelected ? 2.0 : 1.2,
            ),
            boxShadow: [
              if (isActive)
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 18,
                  spreadRadius: 2,
                )
              else if (isSelected)
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
                      const SizedBox(width: 20),

                    // Output Ports Column
                    Column(
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNodeHeader(GraphNode node, bool isActive) {
    IconData icon;
    Color iconColor;

    switch (node.type) {
      case 'start':
        icon = Icons.play_circle_filled;
        iconColor = AppColors.success;
        break;
      case 'end':
      case 'mission_end':
        icon = Icons.stop_circle;
        iconColor = const Color(0xFFDC2626);
        break;
      case 'navigate_waypoint':
      case 'navigate_coordinates':
        icon = Icons.navigation;
        iconColor = const Color(0xFF2563EB);
        break;
      case 'patrol_loop':
        icon = Icons.sync_rounded;
        iconColor = const Color(0xFF3B82F6);
        break;
      case 'relocalize':
        icon = Icons.my_location;
        iconColor = const Color(0xFF2563EB);
        break;
      case 'cancel_navigation':
        icon = Icons.cancel;
        iconColor = const Color(0xFFDC2626);
        break;
      case 'wait':
        icon = Icons.timer;
        iconColor = AppColors.warning;
        break;
      case 'dock':
        icon = Icons.battery_charging_full;
        iconColor = const Color(0xFF16A34A);
        break;
      case 'undock':
        icon = Icons.power_settings_new;
        iconColor = const Color(0xFF059669);
        break;
      case 'jog_motion':
        icon = Icons.gamepad_outlined;
        iconColor = const Color(0xFFD97706);
        break;
      case 'emergency_stop':
        icon = Icons.warning_amber_rounded;
        iconColor = const Color(0xFFDC2626);
        break;
      case 'loop':
      case 'loop_counter':
        icon = Icons.loop_rounded;
        iconColor = const Color(0xFF7C3AED);
        break;
      case 'condition':
        icon = Icons.call_split;
        iconColor = const Color(0xFFEA580C);
        break;
      case 'battery_guard':
        icon = Icons.battery_saver;
        iconColor = const Color(0xFF059669);
        break;
      case 'set_variable':
        icon = Icons.data_object;
        iconColor = const Color(0xFF9333EA);
        break;
      case 'ui_interaction':
        icon = Icons.touch_app;
        iconColor = AppColors.primary;
        break;
      case 'ui_choice':
        icon = Icons.ads_click;
        iconColor = AppColors.primary;
        break;
      case 'ui_media':
        icon = Icons.perm_media_outlined;
        iconColor = const Color(0xFF0284C7);
        break;
      case 'ui_speech':
        icon = Icons.record_voice_over_outlined;
        iconColor = const Color(0xFF8B5CF6);
        break;
      case 'notify':
        icon = Icons.notifications_active;
        iconColor = const Color(0xFF0D9488);
        break;
      case 'call_api':
        icon = Icons.http;
        iconColor = const Color(0xFF7C3AED);
        break;
      case 'call_service':
      case 'call_action':
        icon = Icons.smart_toy;
        iconColor = const Color(0xFF4F46E5);
        break;
      case 'publish_topic':
        icon = Icons.podcasts;
        iconColor = const Color(0xFF4F46E5);
        break;
      case 'switch_mission':
      case 'redirect_mission':
        icon = Icons.alt_route_rounded;
        iconColor = const Color(0xFF009688);
        break;
      default:
        icon = Icons.circle;
        iconColor = AppColors.textSecondary;
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
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              node.label.isNotEmpty ? node.label : node.type,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isActive && widget.isRunning)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'RUNNING',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
              child: const Icon(Icons.close_rounded, size: 16, color: AppColors.textTertiary),
            ),
        ],
      ),
    );
  }

  Widget _buildNodeSummary(GraphNode node) {
    String summary = '';
    switch (node.type) {
      case 'start':
        summary = 'Mission starts here';
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
                Text(
                  port.label,
                  style: TextStyle(
                    color: activeColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
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
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.success,
          boxShadow: [
            BoxShadow(
              color: AppColors.success.withValues(alpha: 0.6),
              blurRadius: 6,
            ),
          ],
        ),
        child: const Center(
          child: Icon(Icons.check, size: 8, color: Colors.white),
        ),
      );
    }
    if (isHoverInvalid) {
      return Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.danger,
          boxShadow: [
            BoxShadow(
              color: AppColors.danger.withValues(alpha: 0.6),
              blurRadius: 6,
            ),
          ],
        ),
        child: const Center(
          child: Icon(Icons.close, size: 8, color: Colors.white),
        ),
      );
    }

    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? Colors.white : color,
        border: Border.all(
          color: isActive ? AppColors.primary : Colors.white.withValues(alpha: 0.8),
          width: 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 3,
            spreadRadius: 0.5,
          ),
        ],
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

      // Remove any existing edge from this output port (each output port typically has 1 edge)
      widget.graph.edges.removeWhere(
        (e) => e.fromNode == fromNodeId && e.fromPort == fromPortId,
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

/// Custom Painter for Bézier Edges and In-Progress Cable.
class _EdgesPainter extends CustomPainter {
  _EdgesPainter({
    required this.graph,
    required this.portOffsets,
    this.selectedEdge,
    this.activeNodeId,
    this.drawingFromOffset,
    this.drawingCurrentOffset,
    this.drawingFromIsInput = false,
    this.drawingColor = const Color(0xFF4CAF50),
    this.isValidTarget,
  });

  final MissionGraph graph;
  final Map<String, Offset> portOffsets;
  final GraphEdge? selectedEdge;
  final String? activeNodeId;
  final Offset? drawingFromOffset;
  final Offset? drawingCurrentOffset;
  final bool drawingFromIsInput;
  final Color drawingColor;
  final bool? isValidTarget;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw saved edges
    for (final edge in graph.edges) {
      final fromKey = '${edge.fromNode}_out_${edge.fromPort}';
      final toKey = '${edge.toNode}_in_${edge.toPort}';

      final p1 = portOffsets[fromKey] ??
          _estimateNodePortOffset(edge.fromNode, edge.fromPort, false);
      final p2 = portOffsets[toKey] ??
          _estimateNodePortOffset(edge.toNode, edge.toPort, true);

      final isSelected = selectedEdge?.id == edge.id;
      final isActive = activeNodeId == edge.fromNode;

      Color edgeColor = const Color(0xFF94A3B8);
      if (edge.fromPort == 'failed' || edge.fromPort == 'false') {
        edgeColor = AppColors.danger;
      } else if (edge.fromPort == 'timeout') {
        edgeColor = AppColors.warning;
      } else if (edge.fromPort == 'submitted' || edge.fromPort == 'true' || edge.fromPort == 'arrived') {
        edgeColor = AppColors.success;
      }

      if (isSelected) {
        edgeColor = AppColors.danger;
      } else if (isActive) {
        edgeColor = AppColors.primary;
      }

      _drawCubicBezier(canvas, p1, p2, edgeColor, isSelected ? 3.0 : (isActive ? 2.8 : 2.0));
    }

    // 2. Draw live wire in progress
    if (drawingFromOffset != null && drawingCurrentOffset != null) {
      final p1 = drawingFromIsInput ? drawingCurrentOffset! : drawingFromOffset!;
      final p2 = drawingFromIsInput ? drawingFromOffset! : drawingCurrentOffset!;

      Color wireColor = drawingColor.withValues(alpha: 0.9);
      double wireWidth = 2.2;
      bool isDashed = false;

      if (isValidTarget == true) {
        wireColor = AppColors.success;
        wireWidth = 3.2;
      } else if (isValidTarget == false) {
        wireColor = AppColors.danger;
        wireWidth = 2.4;
        isDashed = true;
      }

      if (isDashed) {
        _drawDashedCubicBezier(canvas, p1, p2, wireColor, wireWidth);
      } else {
        _drawCubicBezier(canvas, p1, p2, wireColor, wireWidth);
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
      return Offset(node.position.dx + 224.0, y);
    }
  }

  void _drawCubicBezier(Canvas canvas, Offset p1, Offset p2, Color color, double width) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dx = (p2.dx - p1.dx).abs() * 0.5;
    final cp1 = Offset(p1.dx + math.max(dx, 40), p1.dy);
    final cp2 = Offset(p2.dx - math.max(dx, 40), p2.dy);

    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);

    canvas.drawPath(path, paint);

    // Draw small directional circle at center
    final midX = 0.5 * (p1.dx + p2.dx);
    final midY = 0.5 * (p1.dy + p2.dy);
    final arrowPaint = Paint()..color = color..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(midX, midY), width + 1.5, arrowPaint);
  }

  void _drawDashedCubicBezier(Canvas canvas, Offset p1, Offset p2, Color color, double width) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dx = (p2.dx - p1.dx).abs() * 0.5;
    final cp1 = Offset(p1.dx + math.max(dx, 40), p1.dy);
    final cp2 = Offset(p2.dx - math.max(dx, 40), p2.dy);

    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);

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
      ..color = AppColors.borderStrong.withValues(alpha: 0.65)
      ..strokeWidth = 1.5;

    const double spacing = 32.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
