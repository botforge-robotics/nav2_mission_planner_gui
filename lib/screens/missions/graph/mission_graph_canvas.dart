import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'mission_graph_models.dart';

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
  });

  final MissionGraph graph;
  final GraphNode? selectedNode;
  final ValueChanged<GraphNode?> onSelectNode;
  final VoidCallback onGraphChanged;
  final String? activeNodeId;
  final bool readOnly;

  @override
  State<MissionGraphCanvas> createState() => _MissionGraphCanvasState();
}

class _MissionGraphCanvasState extends State<MissionGraphCanvas> {
  final TransformationController _transformController = TransformationController();

  // Wire drawing state
  GraphNode? _drawingFromNode;
  NodePort? _drawingFromPort;
  Offset? _drawingCurrentPos;

  // Selected edge for deletion
  GraphEdge? _selectedEdge;

  // Map to store calculated port offsets on canvas
  final Map<String, Offset> _portOffsets = {};

  void _recordPortOffset(String key, Offset offset) {
    _portOffsets[key] = offset;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF141820),
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
              child: SizedBox(
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
                              ? _portOffsets['${_drawingFromNode!.id}_out_${_drawingFromPort!.id}']
                              : null,
                          drawingCurrentOffset: _drawingCurrentPos,
                          drawingColor: _drawingFromPort?.color ?? const Color(0xFF4CAF50),
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

          // Edge Deletion Quick Banner
          if (_selectedEdge != null && !widget.readOnly)
            Positioned(
              top: 16,
              left: 16,
              child: Card(
                color: const Color(0xFF262E3D),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Color(0xFFF44336)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.link_off, color: Color(0xFFF44336), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Connection selected: ${_selectedEdge!.fromNode} → ${_selectedEdge!.toNode}',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFF44336),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () {
                          setState(() {
                            widget.graph.edges.remove(_selectedEdge);
                            _selectedEdge = null;
                          });
                          widget.onGraphChanged();
                        },
                        icon: const Icon(Icons.delete, size: 14),
                        label: const Text('Delete Edge'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16, color: Colors.grey),
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
              color: const Color(0xFF1F2430),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 4,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.white),
                    tooltip: 'Zoom In',
                    onPressed: () {
                      final matrix = _transformController.value.clone();
                      matrix.scaleByDouble(1.2, 1.2, 1.0, 1.0);
                      _transformController.value = matrix;
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove, color: Colors.white),
                    tooltip: 'Zoom Out',
                    onPressed: () {
                      final matrix = _transformController.value.clone();
                      matrix.scaleByDouble(0.8, 0.8, 1.0, 1.0);
                      _transformController.value = matrix;
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.center_focus_strong, color: Colors.white),
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
            color: const Color(0xFF1E232F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive
                  ? const Color(0xFF00E5FF)
                  : isSelected
                      ? const Color(0xFF448AFF)
                      : const Color(0xFF333D50),
              width: isActive ? 2.5 : isSelected ? 2.0 : 1.0,
            ),
            boxShadow: [
              if (isActive)
                BoxShadow(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.35),
                  blurRadius: 18,
                  spreadRadius: 2,
                )
              else if (isSelected)
                BoxShadow(
                  color: const Color(0xFF448AFF).withValues(alpha: 0.25),
                  blurRadius: 12,
                )
              else
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
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

              const Divider(height: 1, color: Color(0xFF2B3444)),

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
        iconColor = const Color(0xFF4CAF50);
        break;
      case 'navigate_waypoint':
      case 'navigate_coordinates':
        icon = Icons.navigation;
        iconColor = const Color(0xFF2196F3);
        break;
      case 'wait':
        icon = Icons.timer;
        iconColor = const Color(0xFFFF9800);
        break;
      case 'dock':
      case 'undock':
        icon = Icons.battery_charging_full;
        iconColor = const Color(0xFF00E676);
        break;
      case 'ui_interaction':
        icon = Icons.touch_app;
        iconColor = const Color(0xFFE040FB);
        break;
      case 'condition':
        icon = Icons.call_split;
        iconColor = const Color(0xFFFFD600);
        break;
      case 'call_api':
        icon = Icons.http;
        iconColor = const Color(0xFF00B0FF);
        break;
      case 'call_service':
      case 'call_action':
        icon = Icons.smart_toy;
        iconColor = const Color(0xFFFF6D00);
        break;
      case 'notify':
        icon = Icons.notifications_active;
        iconColor = const Color(0xFFFF5252);
        break;
      default:
        icon = Icons.circle;
        iconColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF262E3D),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(11),
          topRight: Radius.circular(11),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              node.label.isNotEmpty ? node.label : node.type,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'RUNNING',
                style: TextStyle(
                  color: Color(0xFF00E5FF),
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
                  if (widget.selectedNode?.id == node.id) {
                    widget.onSelectNode(null);
                  }
                });
                widget.onGraphChanged();
              },
              child: const Icon(Icons.close, size: 16, color: Colors.grey),
            ),
        ],
      ),
    );
  }

  Widget _buildNodeSummary(GraphNode node) {
    String summary = '';
    switch (node.type) {
      case 'start':
        summary = 'Entrypoint';
        break;
      case 'navigate_waypoint':
        summary = 'Target: ${node.params['waypoint'] ?? 'None'}';
        break;
      case 'navigate_coordinates':
        summary = 'X: ${node.params['x'] ?? 0}, Y: ${node.params['y'] ?? 0}';
        break;
      case 'wait':
        summary = 'Duration: ${node.params['duration_sec'] ?? 5}s';
        break;
      case 'dock':
        summary = 'Dock via AprilTag';
        break;
      case 'undock':
        summary = 'Back away from charger';
        break;
      case 'condition':
        summary = 'If: ${node.params['expression'] ?? 'True'}';
        break;
      case 'call_api':
        summary = '${node.params['method'] ?? 'POST'} ${node.params['url'] ?? ''}';
        break;
      case 'ui_interaction':
        final subtype = node.params['subtype'] ?? 'dynamic_form';
        final title = node.params['title'] ?? 'Form';
        summary = '[$subtype] $title';
        break;
      case 'notify':
        summary = node.params['oled_text'] ?? 'Notification';
        break;
      default:
        summary = node.type;
    }

    return Text(
      summary,
      style: const TextStyle(color: Color(0xFF9AA7BD), fontSize: 11),
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

    // Compute center anchor of port
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = context.findRenderObject() as RenderBox?;
      if (box != null) {
        // Approximate port relative offset
        final portOffset = Offset(
          node.position.dx + (isInput ? 8.0 : 232.0),
          node.position.dy + 80.0,
        );
        _recordPortOffset(portKey, portOffset);
      }
    });

    return GestureDetector(
      onPanStart: isInput || widget.readOnly
          ? null
          : (details) {
              setState(() {
                _drawingFromNode = node;
                _drawingFromPort = port;
                _drawingCurrentPos = node.position + Offset(240, 80);
              });
            },
      onPanUpdate: isInput || widget.readOnly
          ? null
          : (details) {
              setState(() {
                _drawingCurrentPos = (_drawingCurrentPos ?? node.position) + details.delta;
              });
            },
      onPanEnd: isInput || widget.readOnly
          ? null
          : (details) {
              _finishWireDrawing();
            },
      child: MouseRegion(
        cursor: isInput ? SystemMouseCursors.click : SystemMouseCursors.precise,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: port.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: port.color.withValues(alpha: 0.6), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isInput) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: port.color),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                port.label,
                style: TextStyle(
                  color: port.color,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!isInput) ...[
                const SizedBox(width: 4),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: port.color),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _finishWireDrawing() {
    if (_drawingFromNode == null || _drawingFromPort == null || _drawingCurrentPos == null) {
      setState(() {
        _drawingFromNode = null;
        _drawingFromPort = null;
        _drawingCurrentPos = null;
      });
      return;
    }

    // Find node closest to release point
    for (final targetNode in widget.graph.nodes) {
      if (targetNode.id == _drawingFromNode!.id) continue;

      final targetRect = Rect.fromLTWH(
        targetNode.position.dx,
        targetNode.position.dy,
        240,
        150,
      );

      if (targetRect.contains(_drawingCurrentPos!)) {
        // Connect to target node input
        final newEdge = GraphEdge(
          id: 'e_${_drawingFromNode!.id}_${_drawingFromPort!.id}_${targetNode.id}',
          fromNode: _drawingFromNode!.id,
          fromPort: _drawingFromPort!.id,
          toNode: targetNode.id,
          toPort: 'in',
        );

        // Remove any existing edge from this port
        widget.graph.edges.removeWhere(
          (e) => e.fromNode == _drawingFromNode!.id && e.fromPort == _drawingFromPort!.id,
        );

        setState(() {
          widget.graph.edges.add(newEdge);
        });
        widget.onGraphChanged();
        break;
      }
    }

    setState(() {
      _drawingFromNode = null;
      _drawingFromPort = null;
      _drawingCurrentPos = null;
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
    this.drawingColor = const Color(0xFF4CAF50),
  });

  final MissionGraph graph;
  final Map<String, Offset> portOffsets;
  final GraphEdge? selectedEdge;
  final String? activeNodeId;
  final Offset? drawingFromOffset;
  final Offset? drawingCurrentOffset;
  final Color drawingColor;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw saved edges
    for (final edge in graph.edges) {
      final fromKey = '${edge.fromNode}_out_${edge.fromPort}';
      final toKey = '${edge.toNode}_in_${edge.toPort}';

      final p1 = portOffsets[fromKey] ??
          _estimateNodePortOffset(edge.fromNode, false);
      final p2 = portOffsets[toKey] ??
          _estimateNodePortOffset(edge.toNode, true);

      final isSelected = selectedEdge?.id == edge.id;
      final isActive = activeNodeId == edge.fromNode;

      Color edgeColor = const Color(0xFF64B5F6);
      if (edge.fromPort == 'failed' || edge.fromPort == 'false') {
        edgeColor = const Color(0xFFF44336);
      } else if (edge.fromPort == 'timeout') {
        edgeColor = const Color(0xFFFF9800);
      } else if (edge.fromPort == 'submitted' || edge.fromPort == 'true' || edge.fromPort == 'arrived') {
        edgeColor = const Color(0xFF4CAF50);
      }

      if (isSelected) {
        edgeColor = Colors.amber;
      } else if (isActive) {
        edgeColor = const Color(0xFF00E5FF);
      }

      _drawCubicBezier(canvas, p1, p2, edgeColor, isSelected ? 3.0 : (isActive ? 2.5 : 1.8));
    }

    // 2. Draw live wire in progress
    if (drawingFromOffset != null && drawingCurrentOffset != null) {
      _drawCubicBezier(
        canvas,
        drawingFromOffset!,
        drawingCurrentOffset!,
        drawingColor.withValues(alpha: 0.85),
        2.0,
      );
    }
  }

  Offset _estimateNodePortOffset(String nodeId, bool isInput) {
    final node = graph.nodes.firstWhere((n) => n.id == nodeId, orElse: () => GraphNode(id: '', type: '', position: Offset.zero));
    return Offset(
      node.position.dx + (isInput ? 0.0 : 240.0),
      node.position.dy + 80.0,
    );
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

    // Draw small directional arrow at center
    final midX = 0.5 * (p1.dx + p2.dx);
    final midY = 0.5 * (p1.dy + p2.dy);
    final arrowPaint = Paint()..color = color..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(midX, midY), width + 1.5, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _EdgesPainter oldDelegate) => true;
}

/// Subtle Dot Grid Background Painter.
class _GridBackgroundPainter extends CustomPainter {
  const _GridBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = const Color(0xFF222836)
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
