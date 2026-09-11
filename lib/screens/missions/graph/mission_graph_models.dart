import 'dart:ui';

/// Port definition on a node (Input or Output).
class NodePort {
  const NodePort({
    required this.id,
    required this.label,
    required this.isInput,
    this.color = const Color(0xFF4CAF50),
  });

  final String id;
  final String label;
  final bool isInput;
  final Color color;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'is_input': isInput,
      };

  factory NodePort.fromJson(Map<String, dynamic> json, {required bool isInput}) {
    final id = json['id'] as String? ?? 'next';
    final label = json['label'] as String? ?? id;
    Color color = const Color(0xFF4CAF50);
    if (id == 'failed' || id == 'failure' || id == 'false' || id == 'low_battery') {
      color = const Color(0xFFF44336);
    } else if (id == 'timeout' || id == 'interrupted') {
      color = const Color(0xFFFF9800);
    } else if (id == 'cancelled' || id == 'skipped') {
      color = const Color(0xFF9E9E9E);
    } else if (isInput || id == 'next' || id == 'in' || id == 'loop_body') {
      color = const Color(0xFF2196F3);
    }
    return NodePort(id: id, label: label, isInput: isInput, color: color);
  }
}

/// Dynamic Form Field Definition for UI Interaction nodes.
class FormFieldDef {
  FormFieldDef({
    required this.key,
    required this.label,
    this.type = 'text', // text, number, select, checkbox, switch, signature
    this.required = false,
    this.options = const [],
    this.defaultValue,
  });

  String key;
  String label;
  String type;
  bool required;
  List<String> options;
  dynamic defaultValue;

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'type': type,
        'required': required,
        if (options.isNotEmpty) 'options': options,
        if (defaultValue != null) 'default_value': defaultValue,
      };

  factory FormFieldDef.fromJson(Map<String, dynamic> json) {
    return FormFieldDef(
      key: json['key'] as String? ?? 'field',
      label: json['label'] as String? ?? 'Field',
      type: json['type'] as String? ?? 'text',
      required: json['required'] as bool? ?? false,
      options: (json['options'] as List? ?? const []).map((e) => e.toString()).toList(),
      defaultValue: json['default_value'],
    );
  }
}

/// A node in the visual mission graph.
class GraphNode {
  GraphNode({
    required this.id,
    required this.type,
    this.label = '',
    required this.position,
    Map<String, dynamic>? params,
  }) : params = params ?? {};

  final String id;
  final String type;
  String label;
  Offset position;
  final Map<String, dynamic> params;

  List<NodePort> get inputPorts => type == 'start'
      ? const []
      : const [NodePort(id: 'in', label: 'In', isInput: true, color: Color(0xFF2196F3))];

  List<NodePort> get outputPorts {
    switch (type) {
      case 'start':
      case 'wait':
      case 'set_variable':
      case 'notify':
        return const [NodePort(id: 'next', label: 'Next', isInput: false, color: Color(0xFF4CAF50))];
      case 'end':
      case 'mission_end':
        return const []; // Terminal node
      case 'loop':
      case 'loop_counter':
        return const [
          NodePort(id: 'loop_body', label: 'Loop Body', isInput: false, color: Color(0xFF2196F3)),
          NodePort(id: 'completed', label: 'Completed', isInput: false, color: Color(0xFF4CAF50)),
        ];
      case 'battery_guard':
        return const [
          NodePort(id: 'ok', label: 'Battery OK', isInput: false, color: Color(0xFF4CAF50)),
          NodePort(id: 'low_battery', label: 'Low Battery', isInput: false, color: Color(0xFFF44336)),
        ];
      case 'patrol_loop':
        return const [
          NodePort(id: 'completed', label: 'Completed', isInput: false, color: Color(0xFF4CAF50)),
          NodePort(id: 'failed', label: 'Failed', isInput: false, color: Color(0xFFF44336)),
          NodePort(id: 'interrupted', label: 'Interrupted', isInput: false, color: Color(0xFFFF9800)),
        ];
      case 'navigate_waypoint':
      case 'navigate_coordinates':
        return const [
          NodePort(id: 'arrived', label: 'Arrived', isInput: false, color: Color(0xFF4CAF50)),
          NodePort(id: 'failed', label: 'Failed', isInput: false, color: Color(0xFFF44336)),
          NodePort(id: 'timeout', label: 'Timeout', isInput: false, color: Color(0xFFFF9800)),
        ];
      case 'dock':
        return const [
          NodePort(id: 'docked', label: 'Docked', isInput: false, color: Color(0xFF4CAF50)),
          NodePort(id: 'failed', label: 'Failed', isInput: false, color: Color(0xFFF44336)),
        ];
      case 'undock':
        return const [
          NodePort(id: 'undocked', label: 'Undocked', isInput: false, color: Color(0xFF4CAF50)),
          NodePort(id: 'failed', label: 'Failed', isInput: false, color: Color(0xFFF44336)),
        ];
      case 'condition':
        return const [
          NodePort(id: 'true', label: 'True', isInput: false, color: Color(0xFF4CAF50)),
          NodePort(id: 'false', label: 'False', isInput: false, color: Color(0xFFF44336)),
        ];
      case 'call_api':
      case 'call_service':
        return const [
          NodePort(id: 'success', label: 'Success', isInput: false, color: Color(0xFF4CAF50)),
          NodePort(id: 'failure', label: 'Failure', isInput: false, color: Color(0xFFF44336)),
        ];
      case 'call_action':
        return const [
          NodePort(id: 'succeeded', label: 'Succeeded', isInput: false, color: Color(0xFF4CAF50)),
          NodePort(id: 'failed', label: 'Failed', isInput: false, color: Color(0xFFF44336)),
        ];
      case 'publish_topic':
        return const [NodePort(id: 'next', label: 'Next', isInput: false, color: Color(0xFF4CAF50))];
      case 'relocalize':
        return const [
          NodePort(id: 'success', label: 'Success', isInput: false, color: Color(0xFF4CAF50)),
          NodePort(id: 'failed', label: 'Failed', isInput: false, color: Color(0xFFF44336)),
        ];
      case 'cancel_navigation':
      case 'emergency_stop':
      case 'jog_motion':
        return const [NodePort(id: 'next', label: 'Next', isInput: false, color: Color(0xFF4CAF50))];
      case 'ui_media':
        return const [
          NodePort(id: 'completed', label: 'Completed', isInput: false, color: Color(0xFF4CAF50)),
          NodePort(id: 'skipped', label: 'Skipped', isInput: false, color: Color(0xFF9E9E9E)),
          NodePort(id: 'timeout', label: 'Timeout', isInput: false, color: Color(0xFFFF9800)),
        ];
      case 'ui_speech':
        return const [
          NodePort(id: 'done', label: 'Done', isInput: false, color: Color(0xFF4CAF50)),
        ];
      case 'ui_choice':
        final opts = (params['options'] as List? ?? ['Yes', 'No']).map((e) => e.toString()).toList();
        return [
          for (final opt in opts)
            NodePort(id: opt.toLowerCase(), label: opt, isInput: false, color: const Color(0xFF4CAF50)),
          const NodePort(id: 'timeout', label: 'Timeout', isInput: false, color: Color(0xFFFF9800)),
        ];
      case 'ui_interaction':
        final subtype = params['subtype'] as String? ?? 'dynamic_form';
        if (subtype == 'choice') {
          final opts = (params['options'] as List? ?? ['Yes', 'No']).map((e) => e.toString()).toList();
          return [
            for (final opt in opts)
              NodePort(id: opt.toLowerCase(), label: opt, isInput: false, color: const Color(0xFF4CAF50)),
            const NodePort(id: 'timeout', label: 'Timeout', isInput: false, color: Color(0xFFFF9800)),
          ];
        }
        return const [
          NodePort(id: 'submitted', label: 'Submitted', isInput: false, color: Color(0xFF4CAF50)),
          NodePort(id: 'cancelled', label: 'Cancelled', isInput: false, color: Color(0xFF9E9E9E)),
          NodePort(id: 'timeout', label: 'Timeout', isInput: false, color: Color(0xFFFF9800)),
        ];
      default:
        return const [NodePort(id: 'next', label: 'Next', isInput: false, color: Color(0xFF4CAF50))];
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        if (label.isNotEmpty) 'label': label,
        'position': {'x': position.dx, 'y': position.dy},
        if (params.isNotEmpty) 'params': params,
      };

  factory GraphNode.fromJson(Map<String, dynamic> json) {
    final pos = json['position'] as Map<String, dynamic>?;
    final dx = (pos?['x'] as num?)?.toDouble() ?? 100.0;
    final dy = (pos?['y'] as num?)?.toDouble() ?? 100.0;

    return GraphNode(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'start',
      label: json['label'] as String? ?? json['title'] as String? ?? '',
      position: Offset(dx, dy),
      params: (json['params'] as Map<String, dynamic>?) ?? {},
    );
  }
}

/// A directed edge connecting an output port of a node to an input port of another node.
class GraphEdge {
  GraphEdge({
    required this.id,
    required this.fromNode,
    required this.fromPort,
    required this.toNode,
    this.toPort = 'in',
  });

  final String id;
  final String fromNode;
  final String fromPort;
  final String toNode;
  final String toPort;

  Map<String, dynamic> toJson() => {
        'id': id,
        'from_node': fromNode,
        'from_port': fromPort,
        'to_node': toNode,
        'to_port': toPort,
      };

  factory GraphEdge.fromJson(Map<String, dynamic> json) {
    return GraphEdge(
      id: json['id'] as String? ?? '',
      fromNode: json['from_node'] as String? ?? '',
      fromPort: (json['from_port'] as String? ?? 'next').toLowerCase(),
      toNode: json['to_node'] as String? ?? '',
      toPort: (json['to_port'] as String? ?? 'in').toLowerCase(),
    );
  }
}

/// Complete visual graph mission data model.
class MissionGraph {
  MissionGraph({
    required this.id,
    required this.name,
    this.map,
    List<GraphNode>? nodes,
    List<GraphEdge>? edges,
    this.entrypoint,
    Map<String, dynamic>? settings,
  })  : nodes = nodes ?? [],
        edges = edges ?? [],
        settings = settings ?? {};

  final String id;
  String name;
  String? map;
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  String? entrypoint;
  final Map<String, dynamic> settings;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (map != null && map!.isNotEmpty) 'map': map,
        'type': 'graph',
        'entrypoint': entrypoint ?? (nodes.isNotEmpty ? nodes.first.id : null),
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'edges': edges.map((e) => e.toJson()).toList(),
        if (settings.isNotEmpty) 'settings': settings,
      };

  factory MissionGraph.fromJson(Map<String, dynamic> json) {
    final rawNodes = (json['nodes'] as List? ?? const []);
    final rawEdges = (json['edges'] as List? ?? const []);

    return MissionGraph(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled Graph',
      map: json['map'] as String?,
      entrypoint: json['entrypoint'] as String?,
      settings: (json['settings'] as Map<String, dynamic>?) ?? {},
      nodes: [
        for (final n in rawNodes)
          if (n is Map<String, dynamic>) GraphNode.fromJson(n)
      ],
      edges: [
        for (final e in rawEdges)
          if (e is Map<String, dynamic>) GraphEdge.fromJson(e)
      ],
    );
  }

  /// Validation: checks if graph has entrypoint, start node, and valid connections.
  String? validate() {
    if (nodes.isEmpty) return 'Graph must contain at least one node.';
    final hasStart = nodes.any((n) => n.type == 'start');
    if (!hasStart) return 'Graph must have a Mission Start node.';

    final nodeIds = nodes.map((n) => n.id).toSet();
    for (final edge in edges) {
      if (!nodeIds.contains(edge.fromNode)) {
        return 'Edge connects from non-existent node: ${edge.fromNode}';
      }
      if (!nodeIds.contains(edge.toNode)) {
        return 'Edge connects to non-existent node: ${edge.toNode}';
      }
    }
    return null;
  }
}
