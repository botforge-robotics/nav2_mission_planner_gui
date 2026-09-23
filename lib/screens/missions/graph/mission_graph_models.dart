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
        return const [NodePort(id: 'next', label: 'Start First Step', isInput: false, color: Color(0xFF4CAF50))];
      case 'wait':
      case 'set_variable':
      case 'notify':
      case 'publish_topic':
      case 'cancel_navigation':
      case 'emergency_stop':
      case 'jog_motion':
        return const [NodePort(id: 'next', label: 'Next Step', isInput: false, color: Color(0xFF4CAF50))];
      case 'end':
      case 'mission_end':
      case 'dock_and_end':
        return const []; // Terminal node (Mission finishes)
      case 'loop':
      case 'loop_counter':
        return const [
          NodePort(id: 'loop_body', label: 'Do These Steps', isInput: false, color: Color(0xFF2196F3)),
          NodePort(id: 'completed', label: 'When Done Repeating', isInput: false, color: Color(0xFF4CAF50)),
        ];
      case 'battery_guard':
        return const [
          NodePort(id: 'ok', label: 'If Battery OK', isInput: false, color: Color(0xFF4CAF50)),
          NodePort(id: 'low_battery', label: 'If Battery Low', isInput: false, color: Color(0xFFF44336)),
        ];
      case 'patrol_loop':
        return const [
          NodePort(id: 'completed', label: 'When Route Finished', isInput: false, color: Color(0xFF4CAF50)),
          NodePort(id: 'failed', label: 'If Problem Occurred', isInput: false, color: Color(0xFFF44336)),
          NodePort(id: 'interrupted', label: 'If Stopped', isInput: false, color: Color(0xFFFF9800)),
        ];
      case 'navigate_waypoint':
      case 'navigate_coordinates':
        return const [
          NodePort(id: 'arrived', label: 'When Arrived', isInput: false, color: Color(0xFF4CAF50)),
          NodePort(id: 'failed', label: 'If Cannot Reach', isInput: false, color: Color(0xFFF44336)),
          NodePort(id: 'timeout', label: 'If Took Too Long', isInput: false, color: Color(0xFFFF9800)),
        ];
      case 'dock':
        return const [
          NodePort(id: 'docked', label: 'When Plugged In', isInput: false, color: Color(0xFF4CAF50)),
          NodePort(id: 'failed', label: 'If Cannot Dock', isInput: false, color: Color(0xFFF44336)),
        ];
      case 'undock':
        return const [
          NodePort(id: 'undocked', label: 'When Cleared', isInput: false, color: Color(0xFF4CAF50)),
          NodePort(id: 'failed', label: 'If Cannot Leave', isInput: false, color: Color(0xFFF44336)),
        ];
      case 'condition':
        return const [
          NodePort(id: 'true', label: 'If Yes (True)', isInput: false, color: Color(0xFF4CAF50)),
          NodePort(id: 'false', label: 'If No (False)', isInput: false, color: Color(0xFFF44336)),
        ];
      case 'parallel':
      case 'parallel_fork':
        final branchCount = (params['branch_count'] as num?)?.toInt() ?? 2;
        return [
          for (int i = 1; i <= branchCount; i++)
            NodePort(
              id: 'branch_$i',
              label: 'Branch $i',
              isInput: false,
              color: const Color(0xFF00ACC1),
            ),
        ];
      case 'call_api':
      case 'call_service':
      case 'relocalize':
        return const [
          NodePort(id: 'success', label: 'If Successful', isInput: false, color: Color(0xFF4CAF50)),
          NodePort(id: 'failure', label: 'If Problem Occurred', isInput: false, color: Color(0xFFF44336)),
        ];
      case 'call_action':
        return const [
          NodePort(id: 'succeeded', label: 'When Done', isInput: false, color: Color(0xFF4CAF50)),
          NodePort(id: 'failed', label: 'If Failed', isInput: false, color: Color(0xFFF44336)),
        ];
      case 'ui_media':
        return const [
          NodePort(id: 'completed', label: 'When Finished', isInput: false, color: Color(0xFF4CAF50)),
          NodePort(id: 'skipped', label: 'If Person Skipped', isInput: false, color: Color(0xFF9E9E9E)),
          NodePort(id: 'timeout', label: 'If Timed Out', isInput: false, color: Color(0xFFFF9800)),
        ];
      case 'ui_speech':
        return const [
          NodePort(id: 'done', label: 'When Done Speaking', isInput: false, color: Color(0xFF4CAF50)),
        ];
      case 'ui_notification':
        return const [
          NodePort(id: 'confirmed', label: 'When OK Tapped', isInput: false, color: Color(0xFF4CAF50)),
          NodePort(id: 'timeout', label: 'If Timed Out', isInput: false, color: Color(0xFFFF9800)),
        ];
      case 'ui_choice':
        final opts = (params['options'] as List? ?? ['Yes', 'No']).map((e) => e.toString()).toList();
        return [
          for (final opt in opts)
            NodePort(id: opt.toLowerCase(), label: 'If chose "$opt"', isInput: false, color: const Color(0xFF4CAF50)),
          const NodePort(id: 'timeout', label: 'If Timed Out', isInput: false, color: Color(0xFFFF9800)),
        ];
      case 'ui_interaction':
        final subtype = params['subtype'] as String? ?? 'dynamic_form';
        if (subtype == 'choice') {
          final opts = (params['options'] as List? ?? ['Yes', 'No']).map((e) => e.toString()).toList();
          return [
            for (final opt in opts)
              NodePort(id: opt.toLowerCase(), label: 'If chose "$opt"', isInput: false, color: const Color(0xFF4CAF50)),
            const NodePort(id: 'timeout', label: 'If Timed Out', isInput: false, color: Color(0xFFFF9800)),
          ];
        }
        return const [
          NodePort(id: 'submitted', label: 'When Form Submitted', isInput: false, color: Color(0xFF4CAF50)),
          NodePort(id: 'cancelled', label: 'If Cancelled / Skipped', isInput: false, color: Color(0xFF9E9E9E)),
          NodePort(id: 'timeout', label: 'If Timed Out', isInput: false, color: Color(0xFFFF9800)),
        ];
      case 'switch_mission':
      case 'redirect_mission':
        return const [
          NodePort(id: 'out', label: 'When Switched', isInput: false, color: Color(0xFF4CAF50)),
          NodePort(id: 'failed', label: 'If Mission Not Found', isInput: false, color: Color(0xFFF44336)),
        ];
      default:
        return const [NodePort(id: 'next', label: 'Next Step', isInput: false, color: Color(0xFF4CAF50))];
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

  /// Initial / Global Mission Variables defined for the graph.
  Map<String, dynamic> get initialVariables {
    final vars = settings['variables'];
    if (vars is Map<String, dynamic>) return vars;
    if (vars is Map) return Map<String, dynamic>.from(vars);
    return {};
  }

  set initialVariables(Map<String, dynamic> val) {
    settings['variables'] = val;
  }

  /// Returns all available variables (Initial + Node Generated + System Built-in).
  List<AvailableVariable> getAllVariables() {
    final list = <AvailableVariable>[];
    final seen = <String>{};

    void addVar(
      String name,
      String source, {
      bool isSystem = false,
      String? sourceNodeId,
      String valueType = 'string',
      dynamic defaultValue,
      String? description,
    }) {
      final clean = name.trim();
      if (clean.isNotEmpty && !seen.contains(clean)) {
        seen.add(clean);
        list.add(AvailableVariable(
          name: clean,
          source: source,
          isSystem: isSystem,
          sourceNodeId: sourceNodeId,
          valueType: valueType,
          defaultValue: defaultValue,
          description: description,
        ));
      }
    }

    // 1. Initial / Global Mission Variables
    for (final entry in initialVariables.entries) {
      final val = entry.value;
      if (val is Map) {
        addVar(
          entry.key,
          'Mission Variable',
          valueType: val['type']?.toString() ?? 'string',
          defaultValue: val['value'] ?? val['default_value'],
          description: val['description']?.toString(),
        );
      } else {
        addVar(
          entry.key,
          'Mission Variable',
          valueType: val is num ? 'number' : (val is bool ? 'boolean' : 'string'),
          defaultValue: val,
        );
      }
    }

    // 2. Node-Generated Variables
    for (final node in nodes) {
      final label = node.label.isNotEmpty ? node.label : node.id;
      switch (node.type) {
        case 'set_variable':
          final key = node.params['key'] as String? ?? node.params['name'] as String?;
          if (key != null && key.trim().isNotEmpty) {
            final val = node.params['value'];
            addVar(
              key,
              'Set Variable ("$label")',
              sourceNodeId: node.id,
              defaultValue: val,
              valueType: val is num ? 'number' : (val is bool ? 'boolean' : 'string'),
            );
          }
          break;
        case 'loop':
        case 'loop_counter':
          final varName = node.params['variable_name'] as String? ?? 'loop_index';
          if (varName.trim().isNotEmpty) {
            addVar(varName, 'Loop Counter ("$label")', sourceNodeId: node.id, valueType: 'number', defaultValue: 0);
          }
          break;
        case 'ui_interaction':
          final rawFields = node.params['fields'] as List?;
          if (rawFields != null) {
            for (final f in rawFields) {
              if (f is Map) {
                final fid = f['key'] as String? ?? f['id'] as String? ?? f['name'] as String?;
                if (fid != null && fid.trim().isNotEmpty) {
                  final flabel = f['label'] as String? ?? fid;
                  addVar(
                    fid,
                    'Form Field "$flabel" ("$label")',
                    sourceNodeId: node.id,
                    valueType: f['type']?.toString() ?? 'string',
                    defaultValue: f['default_value'] ?? f['defaultValue'],
                  );
                }
              }
            }
          }
          final outVar = node.params['output_variable'] as String? ?? node.params['variable_name'] as String?;
          if (outVar != null && outVar.trim().isNotEmpty) {
            addVar(outVar, 'Form Response ("$label")', sourceNodeId: node.id, valueType: 'object');
          }
          break;
        case 'ui_choice':
          final resultVar = node.params['result_variable'] as String? ?? node.params['variable_name'] as String? ?? 'choice_result';
          if (resultVar.trim().isNotEmpty) {
            addVar(resultVar, 'User Choice ("$label")', sourceNodeId: node.id, valueType: 'string');
          }
          break;
        case 'call_api':
          final apiOut = node.params['output_variable'] as String? ?? node.params['variable_name'] as String? ?? 'api_response';
          if (apiOut.trim().isNotEmpty) {
            addVar(apiOut, 'API Response ("$label")', sourceNodeId: node.id, valueType: 'object');
          }
          break;
        case 'call_service':
          final srvOut = node.params['output_variable'] as String? ?? node.params['variable_name'] as String? ?? 'service_response';
          if (srvOut.trim().isNotEmpty) {
            addVar(srvOut, 'Service Result ("$label")', sourceNodeId: node.id, valueType: 'object');
          }
          break;
        case 'call_action':
          final actOut = node.params['output_variable'] as String? ?? node.params['variable_name'] as String? ?? 'action_result';
          if (actOut.trim().isNotEmpty) {
            addVar(actOut, 'Action Result ("$label")', sourceNodeId: node.id, valueType: 'object');
          }
          break;
      }
    }

    // 3. System Built-in variables
    addVar('battery_pct', 'System Battery Level (0-100)', isSystem: true, valueType: 'number', description: 'Real-time robot battery charge percentage');
    addVar('current_map', 'Active Navigation Map Name', isSystem: true, valueType: 'string', description: 'Name of the currently loaded Nav2 map');
    addVar('current_waypoint', 'Last Reached Waypoint', isSystem: true, valueType: 'string', description: 'Name of the station or waypoint the robot last reached');
    addVar('robot_name', 'Robot Display Name', isSystem: true, valueType: 'string', description: 'Hostname or friendly display name of the robot');
    addVar('robot_ip', 'Robot IP Address', isSystem: true, valueType: 'string', description: 'Current network IP address of the robot');
    addVar('timestamp', 'Current ISO Timestamp', isSystem: true, valueType: 'string', description: 'Formatted date and time of execution');
    addVar('status', 'Robot System Health Status', isSystem: true, valueType: 'string', description: 'General health status (OK, WARN, ERROR)');

    return list;
  }
}

/// Representation of an available variable in the mission graph.
class AvailableVariable {
  const AvailableVariable({
    required this.name,
    required this.source,
    this.isSystem = false,
    this.sourceNodeId,
    this.valueType = 'string',
    this.defaultValue,
    this.description,
  });

  final String name;
  final String source;
  final bool isSystem;
  final String? sourceNodeId;
  final String valueType; // 'string', 'number', 'boolean', 'object'
  final dynamic defaultValue;
  final String? description;
}

