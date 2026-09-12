import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
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
                          drawingColor: _drawingFromPort?.color ?? AppColors.primary,
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
                        'Connection selected: ${_selectedEdge!.fromNode} → ${_selectedEdge!.toNode}',
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
          if (isActive)
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
      _drawCubicBezier(
        canvas,
        drawingFromOffset!,
        drawingCurrentOffset!,
        drawingColor.withValues(alpha: 0.85),
        2.2,
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

    // Draw small directional circle at center
    final midX = 0.5 * (p1.dx + p2.dx);
    final midY = 0.5 * (p1.dy + p2.dy);
    final arrowPaint = Paint()..color = color..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(midX, midY), width + 1.5, arrowPaint);
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
