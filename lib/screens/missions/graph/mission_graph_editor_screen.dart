import "package:flutter/services.dart";
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/connection_provider.dart';
import '../../../services/locations_controller.dart';
import '../../../services/sdk_api_service.dart';
import '../../../theme/app_theme.dart';
import 'mission_graph_canvas.dart';
import 'mission_graph_models.dart';
import 'mission_node_inspector.dart';
import 'ui_interaction_dialog.dart';
import 'ai_mission_assistant_widget.dart';
import '../../../services/ai_mission_agent_service.dart';

/// Validation outcome containing blocking errors and ignorable warnings.
class GraphValidationOutcome {
  const GraphValidationOutcome({
    this.errors = const [],
    this.warnings = const [],
  });

  final List<String> errors;
  final List<String> warnings;

  bool get hasErrors => errors.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
  bool get isValid => !hasErrors && !hasWarnings;
}

/// Full-featured Visual Node-Based Mission Editor & Execution Shell.
class MissionGraphEditorScreen extends StatefulWidget {
  const MissionGraphEditorScreen({
    super.key,
    this.existingMission,
  });

  final Map<String, dynamic>? existingMission;

  @override
  State<MissionGraphEditorScreen> createState() => _MissionGraphEditorScreenState();
}

class _MissionGraphEditorScreenState extends State<MissionGraphEditorScreen> {
  late MissionGraph _graph;
  late final TextEditingController _nameController;
  late final FocusNode _nameFocusNode;
  bool _isEditingName = false;

  GraphNode? _selectedNode;
  GraphEdge? _selectedEdge;
  String? _activeNodeId;
  String? _missionState; // idle, running, waiting_for_user, paused, completed, failed
  String? _currentMap;
  List<String> _availableMaps = [];
  List<Map<String, dynamic>> _availableMissions = [];
  bool _saving = false;
  bool _running = false;
  bool _isModalShowing = false;
  Map<String, dynamic>? _activeRobotInteraction;

  Timer? _statusPoller;

  int _leftTabIndex = 0; // 0 = Node Library, 1 = Variables
  String _nodeSearchQuery = '';
  String _variableSearchQuery = '';
  late final TextEditingController _nodeSearchController;
  late final TextEditingController _variableSearchController;

  SdkApiService? get _api {
    final ip = context.read<ConnectionProvider>().robot?.ip;
    return ip == null ? null : SdkApiService(ip);
  }

  @override
  void initState() {
    super.initState();
    _initGraph();
    _nameController = TextEditingController(text: _graph.name);
    _nameFocusNode = FocusNode();
    _nodeSearchController = TextEditingController();
    _variableSearchController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
      _startExecutionPolling();
    });
  }

  void _initGraph() {
    if (widget.existingMission != null) {
      _graph = MissionGraph.fromJson(widget.existingMission!);
    } else {
      // Default initial graph with entrypoint and a waypoint node
      final startId = 'start_1';
      final wpId = 'nav_1';
      _graph = MissionGraph(
        id: 'graph_${DateTime.now().millisecondsSinceEpoch}',
        name: 'New Node Mission',
        entrypoint: startId,
        nodes: [
          GraphNode(
            id: startId,
            type: 'start',
            label: 'Mission Start',
            position: const Offset(100, 200),
          ),
          GraphNode(
            id: wpId,
            type: 'navigate_waypoint',
            label: 'Go to Waypoint',
            position: const Offset(360, 200),
            params: {'waypoint': '', 'tolerance_m': 0.25},
          ),
        ],
        edges: [
          GraphEdge(id: 'e1', fromNode: startId, fromPort: 'next', toNode: wpId, toPort: 'in'),
        ],
      );
    }
  }

  @override
  void dispose() {
    _statusPoller?.cancel();
    _nameController.dispose();
    _nameFocusNode.dispose();
    _nodeSearchController.dispose();
    _variableSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final api = _api;
    if (api == null) return;

    try {
      final maps = await api.listMaps();
      final active = await api.getCurrentMap();
      final wps = await api.listWaypoints();
      final missions = await api.listMissions();
      LocationsController.instance.value = wps;

      if (mounted) {
        setState(() {
          _availableMaps = maps;
          _currentMap = active;
          _availableMissions = missions;
          _graph.map ??= active;
        });
      }
    } catch (_) {}
  }

  List<String> _getAvailableWaypointNames() {
    final list = LocationsController.instance.value;
    if (list != null && list.isNotEmpty) {
      return list
          .map((e) => (e['name'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return const [];
  }

  void _startExecutionPolling({bool fast = false}) {
    _statusPoller?.cancel();
    final interval = fast
        ? const Duration(milliseconds: 600)
        : const Duration(seconds: 4);
    _statusPoller = Timer.periodic(interval, (t) async {
      final api = _api;
      if (api == null || !mounted) return;

      try {
        final status = await api.missionStatus();
        final state = status['state']?.toString() ?? 'idle';
        final isMissionActive = (state == 'running' || state == 'waiting_for_user' || state == 'paused');
        final activeNode = isMissionActive ? status['active_node_id']?.toString() : null;

        if (mounted) {
          final wasRunning = _running;
          setState(() {
            _missionState = state;
            _activeNodeId = activeNode;
            _running = isMissionActive;
          });

          // Adapt polling speed dynamically: fast while running, relaxed while idle
          if (isMissionActive && !wasRunning) {
            _startExecutionPolling(fast: true);
            return;
          } else if (!isMissionActive && wasRunning) {
            _startExecutionPolling(fast: false);
            return;
          }
        }

        // Check if there's an active UI interaction prompt
        if (state == 'waiting_for_user') {
          final inter = await api.fetchActiveUiInteraction();
          if (inter != null && mounted) {
            final p = inter['params'] as Map<String, dynamic>?;
            final target = (inter['target'] ?? p?['target'] ?? 'robot_screen').toString().toLowerCase();

            if (target == 'robot_screen') {
              if (_activeRobotInteraction?['interaction_id'] != inter['interaction_id']) {
                setState(() => _activeRobotInteraction = inter);
              }
            } else if (!_isModalShowing) {
              setState(() => _activeRobotInteraction = null);
              _isModalShowing = true;
              await UiInteractionDialog.show(
                context,
                api: api,
                interaction: inter,
              );
              _isModalShowing = false;
            }
          }
        } else {
          if (_activeRobotInteraction != null && mounted) {
            setState(() => _activeRobotInteraction = null);
          }
        }

        if (state == 'completed' || state == 'failed' || state == 'cancelled') {
          _statusPoller?.cancel();
        }
      } catch (_) {}
    });
  }

  Future<void> _saveMission() async {
    final api = _api;
    if (api == null) return;

    setState(() => _saving = true);
    _graph.name = _nameController.text.trim().isEmpty ? 'Untitled Graph' : _nameController.text.trim();

    try {
      await api.putGraphMission(_graph.toJson());

      // Auto-sync start node trigger/schedule to robot schedule store
      final startNode = _graph.nodes.cast<GraphNode?>().firstWhere(
        (n) => n?.type == 'start',
        orElse: () => null,
      );
      if (startNode != null) {
        final trigger = startNode.params['trigger'] as String? ?? 'manual';
        final enabled = startNode.params['enabled'] as bool? ?? true;
        final schedId = 'sched_${_graph.id}';

        if (trigger != 'manual' && enabled) {
          final isInterval = trigger == 'interval';
          final schedType = isInterval ? 'interval' : (startNode.params['schedule_type'] as String? ?? 'daily');
          final intervalMins = (startNode.params['interval_minutes'] as num?)?.toInt() ?? 30;
          final hour = isInterval ? 0 : ((startNode.params['schedule_hour'] as num?)?.toInt() ?? 9);
          final minute = isInterval ? intervalMins : ((startNode.params['schedule_minute'] as num?)?.toInt() ?? 0);
          final weekdays = ((startNode.params['weekdays'] as List?)?.cast<int>() ?? const []).toList();
          final date = startNode.params['schedule_date'] as String?;

          try {
            await api.putSchedule(
              schedId,
              missionId: _graph.id,
              name: '${_graph.name} (${isInterval ? "Every ${intervalMins}m" : schedType})',
              hour: hour,
              minute: minute,
              repeat: schedType,
              intervalMinutes: isInterval ? intervalMins : null,
              date: schedType == 'once' ? date : null,
              weekdays: schedType == 'weekly' ? weekdays : const [],
              enabled: true,
            );
          } catch (schedErr) {
            debugPrint('Note: schedule sync result: $schedErr');
          }
        } else {
          // If trigger is manual or disabled, remove any existing schedule record
          try {
            await api.deleteSchedule(schedId);
          } catch (_) {}
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Node mission graph saved successfully!'),
            backgroundColor: Color(0xFF00C853),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _runMission() async {
    final api = _api;
    if (api == null) return;

    // Validate graph first
    final validation = _validateGraph();
    if (validation.hasErrors) {
      await _showValidationDialog(
        errors: validation.errors,
        warnings: validation.warnings,
        canProceed: false,
      );
      return;
    }

    if (validation.hasWarnings) {
      final proceed = await _showValidationDialog(
        errors: const [],
        warnings: validation.warnings,
        canProceed: true,
      );
      if (proceed != true) return;
    }

    // Save first then execute
    await _saveMission();

    try {
      await api.startMission(_graph.id);
      setState(() {
        _running = true;
        _missionState = 'running';
      });
      _startExecutionPolling(fast: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to execute mission: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _cancelMission() async {
    final api = _api;
    if (api == null) return;
    try {
      await api.cancelMission(_graph.id);
      setState(() {
        _running = false;
        _missionState = 'cancelled';
        _activeNodeId = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel mission: $e')),
        );
      }
    }
  }

  Future<void> _deleteMission() async {
    final api = _api;
    if (api == null) return;
    if (_running) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 36),
          title: const Text('Mission is Running'),
          content: const Text('Cannot delete this mission while it is actively executing. Please abort or cancel first.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 36),
        title: const Text('Delete Mission?'),
        content: Text(
          'Are you sure you want to permanently delete "${_graph.name}"?\n\nThis will remove the entire visual node graph and all configured nodes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: const Text('Delete Mission'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await api.deleteMission(_graph.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mission "${_graph.name}" deleted')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete mission: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  GraphValidationOutcome _validateGraph() {
    final errors = <String>[];
    final warnings = <String>[];

    if (_graph.nodes.isEmpty) {
      errors.add('The graph contains no nodes.');
      return GraphValidationOutcome(errors: errors, warnings: warnings);
    }

    // Check entrypoint
    if (_graph.entrypoint == null || !_graph.nodes.any((n) => n.id == _graph.entrypoint)) {
      errors.add('No valid entrypoint node specified.');
    }

    // Check for duplicate node IDs
    final ids = <String>{};
    for (final n in _graph.nodes) {
      if (ids.contains(n.id)) {
        errors.add('Duplicate node ID found: "${n.id}".');
      }
      ids.add(n.id);
    }

    // Check for edge endpoint validity
    for (final e in _graph.edges) {
      if (!ids.contains(e.fromNode)) {
        errors.add('Edge connects from non-existent node: "${e.fromNode}".');
      }
      if (!ids.contains(e.toNode)) {
        errors.add('Edge connects to non-existent node: "${e.toNode}".');
      }
    }

    // Safety validation: Prevent simultaneous conflicting drive/motion actions ONLY in parallel branches
    const motionTypes = {'navigate_waypoint', 'navigate_coordinates', 'patrol_loop', 'dock', 'undock', 'jog_motion'};
    for (final node in _graph.nodes) {
      // NOTE: UI forms (ui_interaction), choices (ui_choice), conditions (condition), etc.
      // execute mutually exclusive branches (user taps ONE button/choice).
      // Motion conflict can ONLY occur if the step is an actual parallel fork!
      final isParallelFork = node.type == 'parallel' || node.type == 'parallel_fork';
      if (!isParallelFork) {
        continue;
      }

      final outgoing = _graph.edges.where((e) => e.fromNode == node.id).toList();
      if (outgoing.length > 1) {
        // Deduplicate target node IDs (in case multiple edges point to the same destination)
        final targetNodeIds = outgoing.map((e) => e.toNode).toSet();
        final targetNodes = targetNodeIds
            .map((id) => _graph.nodes.firstWhere((n) => n.id == id, orElse: () => node))
            .where((n) => n.id != node.id)
            .toList();
        final motionTargets = targetNodes.where((n) => motionTypes.contains(n.type)).toList();
        if (motionTargets.length > 1) {
          final names = motionTargets.map((n) => n.label.isNotEmpty ? n.label : n.id).join(', ');
          final nodeName = node.label.isNotEmpty ? node.label : node.id;
          warnings.add('Parallel Conflict Warning: Step "$nodeName" branches into multiple driving actions ($names) simultaneously. Robot can only drive in one direction at a time.');
        }
      }
    }

    return GraphValidationOutcome(errors: errors, warnings: warnings);
  }

  Future<bool?> _showValidationDialog({
    required List<String> errors,
    required List<String> warnings,
    bool canProceed = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B202C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: errors.isNotEmpty ? AppColors.danger : AppColors.warning,
            width: 1.5,
          ),
        ),
        title: Row(
          children: [
            Icon(
              errors.isNotEmpty ? Icons.error_outline : Icons.warning_amber_rounded,
              color: errors.isNotEmpty ? AppColors.danger : AppColors.warning,
              size: 24,
            ),
            const SizedBox(width: 10),
            Text(
              errors.isNotEmpty ? 'Validation Errors' : 'Validation Warnings',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (errors.isNotEmpty) ...[
                const Text(
                  'The following critical issues must be resolved before running:',
                  style: TextStyle(color: AppColors.danger, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                for (final err in errors)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
                        Expanded(
                          child: Text(err, style: const TextStyle(color: Color(0xFFCFD8DC), fontSize: 12.5)),
                        ),
                      ],
                    ),
                  ),
                if (warnings.isNotEmpty) const SizedBox(height: 12),
              ],
              if (warnings.isNotEmpty) ...[
                Text(
                  errors.isEmpty
                      ? 'The mission planner detected potential warnings. You can safely ignore these warnings if this behavior is intentional (e.g. mutually exclusive buttons or choices):'
                      : 'Additional warnings:',
                  style: TextStyle(
                    color: errors.isEmpty ? AppColors.warning : AppColors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                for (final warn in warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold)),
                        Expanded(
                          child: Text(warn, style: const TextStyle(color: Color(0xFFCFD8DC), fontSize: 12.5)),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              canProceed ? 'Cancel' : 'OK',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          if (canProceed && errors.isEmpty)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Proceed Anyway / Ignore Warning', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
        ],
      ),
    );
  }

  void _addNodeFromCatalog(String type) {
    final timestamp = DateTime.now().millisecondsSinceEpoch.remainder(10000);
    final newId = '${type}_$timestamp';
    Offset pos = const Offset(280, 200);

    if (_graph.nodes.isNotEmpty) {
      final last = _graph.nodes.last;
      pos = Offset(last.position.dx + 60, last.position.dy + 60);
    }

    Map<String, dynamic> defaultParams = {};
    String defaultLabel = type;

    switch (type) {
      case 'start':
        defaultLabel = 'Start Mission';
        defaultParams = {
          'trigger': 'manual',
          'enabled': true,
          'interval_minutes': 30,
          'schedule_type': 'daily',
          'schedule_hour': 9,
          'schedule_minute': 0,
          'weekdays': [0, 1, 2, 3, 4],
          'min_battery': 20.0,
          'skip_if_busy': true,
          'require_active_map': true,
        };
        break;
      case 'end':
      case 'mission_end':
        defaultLabel = 'Finish Mission';
        defaultParams = {'status': 'success', 'message': 'Mission completed successfully.', 'dock_on_end': false};
        break;
      case 'loop':
      case 'loop_counter':
        defaultLabel = 'Repeat Steps';
        defaultParams = {'count': 3, 'variable_name': 'loop_index', 'max_iterations': 50};
        break;
      case 'parallel':
      case 'parallel_fork':
        defaultLabel = 'Run in Parallel';
        defaultParams = {'branch_count': 2};
        break;
      case 'battery_guard':
        defaultLabel = 'Check Battery Level';
        defaultParams = {'min_battery_pct': 20.0, 'require_charging': false};
        break;
      case 'patrol_loop':
        defaultLabel = 'Patrol Route';
        defaultParams = {'waypoints': <String>[], 'laps': 1, 'dwell_sec': 2.0};
        break;
      case 'navigate_waypoint':
        defaultLabel = 'Drive to Saved Place';
        defaultParams = {'waypoint': '', 'tolerance_m': 0.25};
        break;
      case 'navigate_coordinates':
        defaultLabel = 'Drive to Coordinates';
        defaultParams = {'x': 0.0, 'y': 0.0, 'theta': 0.0, 'tolerance_m': 0.25};
        break;
      case 'relocalize':
        defaultLabel = 'Find My Position';
        defaultParams = {'mode': 'global_scan'};
        break;
      case 'cancel_navigation':
        defaultLabel = 'Stop Driving';
        defaultParams = {'halt_type': 'abort_goal'};
        break;
      case 'dock':
        defaultLabel = 'Go to Charger';
        defaultParams = {'timeout_sec': 60.0};
        break;
      case 'undock':
        defaultLabel = 'Leave Charger';
        break;
      case 'jog_motion':
        defaultLabel = 'Nudge / Turn Wheels';
        defaultParams = {'linear_vel': 0.0, 'angular_vel': 0.0, 'duration_sec': 1.0};
        break;
      case 'emergency_stop':
        defaultLabel = 'Safety Stop';
        defaultParams = {'sound_alert': true};
        break;
      case 'wait':
        defaultLabel = 'Pause & Wait';
        defaultParams = {'duration': 5.0};
        break;
      case 'condition':
        defaultLabel = 'Check / If-Else';
        defaultParams = {'expression': "form['status'] == 'Pass'"};
        break;
      case 'ui_interaction':
        defaultLabel = 'Ask for Information';
        defaultParams = {
          'target': 'robot_screen',
          'subtype': 'dynamic_form',
          'title': 'Inspection Checklist',
          'message': 'Please complete the field checklist before proceeding.',
          'timeout_sec': 60.0,
          'fields': [
            {'key': 'inspector_name', 'label': 'Your Name', 'type': 'text', 'required': true},
            {'key': 'status', 'label': 'Checklist Status', 'type': 'select', 'options': ['Pass', 'Fail']},
          ],
        };
        break;
      case 'ui_notification':
        defaultLabel = 'Show Notification';
        defaultParams = {
          'target': 'robot_screen',
          'subtype': 'notification',
          'title': 'Notice',
          'message': 'Robot arrived at destination. Please confirm to proceed.',
          'button_text': 'OK',
          'timeout_sec': 30.0,
          'sound_alert': true,
        };
        break;
      case 'ui_choice':
        defaultLabel = 'Ask Choice (Buttons)';
        defaultParams = {
          'target': 'robot_screen',
          'subtype': 'choice',
          'title': 'Make a Choice',
          'timeout_sec': 60.0,
          'options': ['Yes', 'No']
        };
        break;
      case 'ui_media':
        defaultLabel = 'Show Picture / Video';
        defaultParams = {
          'media_type': 'image',
          'url': 'https://images.unsplash.com/photo-1485827404703-89b55fcc595e',
          'duration_sec': 15.0,
          'show_skip': true,
          'target': 'robot_screen',
        };
        break;
      case 'ui_speech':
        defaultLabel = 'Speak Aloud';
        defaultParams = {'text': 'NavPro Mini has arrived at your station.', 'wait_completion': true};
        break;
      case 'call_api':
        defaultLabel = 'Send Web Notice';
        defaultParams = {
          'method': 'POST',
          'url': 'https://api.example.com/log',
          'bearer_token': '',
          'headers': '{}',
          'payload': '{}',
          'timeout_sec': 10.0
        };
        break;
      case 'call_service':
        defaultLabel = 'Trigger Robot Tool';
        defaultParams = {
          'service_name': '/set_mode',
          'service_type': 'std_srvs/srv/SetBool',
          'payload': '{"data": true}',
          'timeout_sec': 5.0
        };
        break;
      case 'call_action':
        defaultLabel = 'Run Background Task';
        defaultParams = {
          'action_name': '/navigate_to_pose',
          'action_type': 'nav2_msgs/action/NavigateToPose',
          'payload': '{}',
          'timeout_sec': 60.0
        };
        break;
      case 'publish_topic':
        defaultLabel = 'Broadcast Signal';
        defaultParams = {
          'topic_name': '/cmd_vel',
          'message_type': 'geometry_msgs/msg/Twist',
          'payload': '{}'
        };
        break;
      case 'notify':
        defaultLabel = 'Lights & Chime Signal';
        defaultParams = {'line1': 'Station Arrived', 'line2': 'Status OK', 'led_color': '#00E5FF'};
        break;
      case 'set_variable':
        defaultLabel = 'Remember a Value';
        defaultParams = {'key': 'inspected', 'value': true};
        break;
      case 'switch_mission':
      case 'redirect_mission':
        defaultLabel = 'Switch Mission';
        defaultParams = {'target_mission_id': '', 'transfer_context': true};
        break;
      default:
        defaultLabel = type;
    }

    final newNode = GraphNode(
      id: newId,
      type: type,
      label: defaultLabel,
      position: pos,
      params: defaultParams,
    );

    setState(() {
      _graph.nodes.add(newNode);
      _selectedNode = newNode;
    });
  }

  Widget _buildRobotInteractionBanner() {
    final title = _activeRobotInteraction?['title'] ?? 'Operator Action';
    final subtype = _activeRobotInteraction?['subtype'] ?? 'form';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF3EE),
        border: Border(bottom: BorderSide(color: Color(0xFFFFD4C2), width: 1.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.tablet_mac_rounded, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Active on Robot Screen ($subtype): $title',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const Text(
                  'Awaiting physical interaction from on-site user on the robot screen terminal.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              side: const BorderSide(color: AppColors.primary),
              foregroundColor: AppColors.primary,
            ),
            icon: const Icon(Icons.open_in_new, size: 14),
            label: const Text('Respond on Desktop', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            onPressed: () async {
              final api = _api;
              final inter = _activeRobotInteraction;
              if (api != null && inter != null) {
                await UiInteractionDialog.show(context, api: api, interaction: inter);
              }
            },
          ),
        ],
      ),
    );
  }

  void _deleteNode(GraphNode node) {
    if (node.type == 'start') return;
    setState(() {
      _graph.nodes.removeWhere((n) => n.id == node.id);
      _graph.edges.removeWhere((e) => e.fromNode == node.id || e.toNode == node.id);
      if (_graph.entrypoint == node.id) {
        _graph.entrypoint = _graph.nodes.isNotEmpty ? _graph.nodes.first.id : null;
      }
      if (_selectedNode?.id == node.id) {
        _selectedNode = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: Row(
        children: [
          // Left Sidebar with Tabs (Node Library & Variables)
          _buildLeftSidebar(),

          // Center Graph Canvas with robot interaction banner
          Expanded(
            child: Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.delete || event.logicalKey == LogicalKeyboardKey.backspace) {
                    if (_selectedEdge != null && !_running) {
                      setState(() {
                        _graph.edges.remove(_selectedEdge);
                        _selectedEdge = null;
                      });
                      return KeyEventResult.handled;
                    }
                    if (_selectedNode != null && _selectedNode!.type != 'start' && !_running) {
                      _deleteNode(_selectedNode!);
                      return KeyEventResult.handled;
                    }
                  }
                }
                return KeyEventResult.ignored;
              },
              child: Column(
                children: [
                  if (_activeRobotInteraction != null)
                    _buildRobotInteractionBanner(),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: MissionGraphCanvas(
                            key: ValueKey(_graph.id),
                            graph: _graph,
                            selectedNode: _selectedNode,
                            selectedEdge: _selectedEdge,
                            activeNodeId: _activeNodeId,
                            isRunning: _running,
                            onSelectNode: (node) => setState(() {
                              _selectedNode = node;
                              if (node != null) _selectedEdge = null;
                            }),
                            onSelectEdge: (edge) => setState(() {
                              _selectedEdge = edge;
                              if (edge != null) _selectedNode = null;
                            }),
                            onDeleteEdge: (edge) => setState(() {
                              _graph.edges.remove(edge);
                              _selectedEdge = null;
                            }),
                            onGraphChanged: () {
                              setState(() {});
                            },
                          ),
                        ),
                        // Floating Bottom-Right AI Assistant Widget
                        Positioned(
                          right: 16,
                          bottom: 16,
                          child: AiMissionAssistantWidget(
                            availableWaypoints: _getAvailableWaypointNames(),
                            existingGraph: _graph,
                            onGraphGenerated: (newGraph) {
                              setState(() {
                                _graph = newGraph;
                                _nameController.text = newGraph.name;
                                _selectedNode = null;
                                _selectedEdge = null;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: AppColors.surface,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                                    side: const BorderSide(color: AppColors.border, width: 1.2),
                                  ),
                                  elevation: 6,
                                  content: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.auto_awesome, color: AppColors.primary, size: 18),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Workflow generated: "${newGraph.name}" (${newGraph.nodes.length} nodes, ${newGraph.edges.length} edges).',
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Right Inspector
          _buildRightSidebar(_selectedNode),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, thickness: 1, color: AppColors.border),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Row(
        children: [
          const Icon(Icons.account_tree_outlined, color: AppColors.primary, size: 22),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Workflow Editor',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Mission Name: Display as text with pen icon, enters edit mode on click
          !_isEditingName
              ? Tooltip(
                  message: 'Click to edit mission name',
                  child: InkWell(
                    onTap: () {
                      _nameController.text = _graph.name;
                      setState(() => _isEditingName = true);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _nameFocusNode.requestFocus();
                        _nameController.selection = TextSelection(
                          baseOffset: 0,
                          extentOffset: _nameController.text.length,
                        );
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 240),
                            child: Text(
                              _graph.name.isNotEmpty ? _graph.name : 'Untitled Mission',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.edit_outlined,
                            size: 15,
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 220,
                      height: 36,
                      child: TextField(
                        controller: _nameController,
                        focusNode: _nameFocusNode,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Mission Name',
                          hintStyle: const TextStyle(color: AppColors.textTertiary),
                          filled: true,
                          fillColor: AppColors.surfaceSunken,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(color: AppColors.primary),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(color: AppColors.primary),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                          ),
                        ),
                        onSubmitted: (val) {
                          setState(() {
                            final name = val.trim();
                            _graph.name = name.isNotEmpty ? name : 'Untitled Mission';
                            _isEditingName = false;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22),
                      tooltip: 'Save Name',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () {
                        setState(() {
                          final name = _nameController.text.trim();
                          _graph.name = name.isNotEmpty ? name : 'Untitled Mission';
                          _isEditingName = false;
                        });
                      },
                    ),
                  ],
                ),
          const SizedBox(width: 14),

          // Map Selector (Explicitly labeled)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.map_outlined, size: 15, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                const Text(
                  'Map:',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                DropdownButtonHideUnderline(
                  child: Builder(
                    builder: (context) {
                      final mapSet = <String>{
                        ..._availableMaps,
                        if (_currentMap != null && _currentMap!.isNotEmpty) _currentMap!,
                        if (_graph.map != null && _graph.map!.isNotEmpty) _graph.map!,
                      };
                      final mapList = mapSet.toList();
                      final selectedMap = mapSet.contains(_graph.map)
                          ? _graph.map
                          : (mapSet.contains(_currentMap)
                              ? _currentMap
                              : (mapList.isNotEmpty ? mapList.first : null));

                      return DropdownButton<String>(
                        value: selectedMap,
                        dropdownColor: AppColors.surface,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                        hint: const Text('Select Map', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        items: [
                          for (final m in mapList)
                            DropdownMenuItem(value: m, child: Text(m)),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _graph.map = val;
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // Execution Status Pill
        if (_missionState != null && _missionState != 'idle')
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _running ? AppColors.primary.withValues(alpha: 0.1) : AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _running ? AppColors.primary : AppColors.success,
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_running)
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  )
                else
                  const Icon(Icons.check_circle_outline, size: 14, color: AppColors.success),
                const SizedBox(width: 8),
                Text(
                  _missionState!.toUpperCase(),
                  style: TextStyle(
                    color: _running ? AppColors.primary : AppColors.success,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

        // Delete Mission Button (when editing an existing saved mission)
        if (widget.existingMission != null) ...[
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              foregroundColor: AppColors.danger,
              side: BorderSide(color: AppColors.danger.withValues(alpha: 0.4)),
            ),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Delete'),
            onPressed: _deleteMission,
          ),
          const SizedBox(width: 8),
        ],

        // Validate Button
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            foregroundColor: AppColors.textSecondary,
            side: const BorderSide(color: AppColors.border),
          ),
          icon: const Icon(Icons.verified_outlined, size: 18),
          label: const Text('Validate'),
          onPressed: () {
            final validation = _validateGraph();
            if (validation.isValid) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Graph structure is valid!'), backgroundColor: AppColors.success),
              );
            } else {
              _showValidationDialog(
                errors: validation.errors,
                warnings: validation.warnings,
                canProceed: !validation.hasErrors,
              );
            }
          },
        ),
        const SizedBox(width: 8),

        // Auto-Align Button
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            foregroundColor: AppColors.textSecondary,
            side: const BorderSide(color: AppColors.border),
          ),
          icon: const Icon(Icons.auto_fix_high_rounded, size: 17, color: AppColors.primary),
          label: const Text('Auto-Align'),
          onPressed: () {
            setState(() {
              AiMissionAgentService.applyCleanGraphLayout(_graph);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Graph layout neatly aligned and reorganized.'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
        const SizedBox(width: 8),

        // Save Button
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            backgroundColor: AppColors.surfaceSunken,
            foregroundColor: AppColors.textPrimary,
          ),
          icon: _saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
              : const Icon(Icons.save_outlined, size: 18),
          label: const Text('Save'),
          onPressed: _saving ? null : _saveMission,
        ),
        const SizedBox(width: 10),

        // Run / Cancel Button
        if (_running)
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.stop_rounded, size: 18),
            label: const Text('Abort Mission'),
            onPressed: _cancelMission,
          )
        else
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textOnPrimary,
            ),
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Execute Graph'),
            onPressed: _runMission,
          ),
        const SizedBox(width: 16),
      ],
    );
  }

  static const List<Map<String, dynamic>> _catalogCategories = [
    {
      'title': 'Where to Drive',
      'items': [
        _PaletteItem('navigate_waypoint', 'Drive to Saved Place', 'Go to named room or spot', Icons.place_outlined, Color(0xFF2563EB)),
        _PaletteItem('navigate_coordinates', 'Drive to Coordinates', 'Drive to exact (X, Y) map spot', Icons.navigation_outlined, Color(0xFF0284C7)),
        _PaletteItem('patrol_loop', 'Patrol Route', 'Visit places in sequence (rounds)', Icons.sync_rounded, Color(0xFF3B82F6)),
        _PaletteItem('relocalize', 'Find My Position', 'Scan room with laser to locate self', Icons.my_location, Color(0xFF2563EB)),
        _PaletteItem('cancel_navigation', 'Stop Driving', 'Cancel current drive & halt', Icons.cancel_outlined, Color(0xFFDC2626)),
      ],
    },
    {
      'title': 'Charging & Movement',
      'items': [
        _PaletteItem('dock', 'Go to Charger', 'Drive to dock and start charging', Icons.battery_charging_full, Color(0xFF16A34A)),
        _PaletteItem('undock', 'Leave Charger', 'Safely back away from dock', Icons.power_settings_new, Color(0xFF059669)),
        _PaletteItem('jog_motion', 'Nudge / Turn Wheels', 'Drive forward/back or turn briefly', Icons.gamepad_outlined, Color(0xFFD97706)),
        _PaletteItem('emergency_stop', 'Safety Stop (E-Stop)', 'Immediately cut motor power', Icons.warning_amber_rounded, Color(0xFFDC2626)),
      ],
    },
    {
      'title': 'Rules & Flow Control',
      'items': [
        _PaletteItem('start', 'Start Mission', 'Where the mission begins', Icons.play_circle_outline, Color(0xFF16A34A)),
        _PaletteItem('end', 'Finish Mission', 'Complete mission and stop safely', Icons.stop_circle_outlined, Color(0xFFDC2626)),
        _PaletteItem('loop', 'Repeat Steps', 'Repeat connected steps multiple times', Icons.loop_rounded, Color(0xFF7C3AED)),
        _PaletteItem('parallel', 'Run in Parallel', 'Execute multiple steps simultaneously', Icons.call_split_rounded, Color(0xFF00ACC1)),
        _PaletteItem('condition', 'Check / If-Else', 'Branch path based on condition', Icons.alt_route, Color(0xFFEA580C)),
        _PaletteItem('wait', 'Pause & Wait', 'Wait a few seconds before next step', Icons.timer_outlined, Color(0xFFD97706)),
        _PaletteItem('battery_guard', 'Check Battery Level', 'Recharge if battery drops too low', Icons.battery_saver, Color(0xFF059669)),
        _PaletteItem('set_variable', 'Remember a Value', 'Save a number, text, or counter', Icons.data_object, Color(0xFF9333EA)),
        _PaletteItem('switch_mission', 'Switch Mission', 'Hand off to another saved mission', Icons.alt_route_rounded, Color(0xFF009688)),
      ],
    },
    {
      'title': 'Screen, Voice & Signals',
      'items': [
        _PaletteItem('ui_notification', 'Show Notification', 'Show notice banner with OK button', Icons.notification_important_outlined, Color(0xFF0284C7)),
        _PaletteItem('ui_interaction', 'Ask for Information', 'Show form on screen to fill out', Icons.touch_app_outlined, AppColors.primary),
        _PaletteItem('ui_choice', 'Ask Choice (Buttons)', 'Show tap buttons on robot screen', Icons.ads_click, AppColors.primary),
        _PaletteItem('ui_media', 'Show Picture or Video', 'Display image/video on robot screen', Icons.perm_media_outlined, Color(0xFF0284C7)),
        _PaletteItem('ui_speech', 'Speak Aloud', 'Say message aloud via speakers', Icons.record_voice_over_outlined, Color(0xFF8B5CF6)),
        _PaletteItem('notify', 'Lights & Chime Signal', 'Play chime or flash LED lights', Icons.tv, Color(0xFF0D9488)),
      ],
    },
    {
      'title': 'External Tools & Signals',
      'items': [
        _PaletteItem('call_api', 'Send Web Notice', 'Send alert/data to a website or app', Icons.http, Color(0xFF7C3AED)),
        _PaletteItem('call_service', 'Trigger Robot Tool', 'Run internal robot function/tool', Icons.settings_remote, Color(0xFF4F46E5)),
        _PaletteItem('call_action', 'Run Background Task', 'Start long task and wait for it', Icons.bolt, Color(0xFF0284C7)),
        _PaletteItem('publish_topic', 'Broadcast Signal', 'Send message to other robot parts', Icons.podcasts, Color(0xFF4F46E5)),
      ],
    },
  ];

  Widget _buildLeftSidebar() {
    final allVars = _graph.getAllVariables();
    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border, width: 1.0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Segmented Tab Switcher (Node Library vs Variables)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  // Tab 0: Node Library
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _leftTabIndex = 0),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _leftTabIndex == 0 ? AppColors.surface : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: _leftTabIndex == 0
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  )
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.widgets_outlined,
                              size: 16,
                              color: _leftTabIndex == 0 ? AppColors.primary : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Node Library',
                              style: TextStyle(
                                color: _leftTabIndex == 0 ? AppColors.textPrimary : AppColors.textSecondary,
                                fontWeight: _leftTabIndex == 0 ? FontWeight.bold : FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Tab 1: Variables
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _leftTabIndex = 1),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _leftTabIndex == 1 ? AppColors.surface : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: _leftTabIndex == 1
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  )
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.data_object_rounded,
                              size: 16,
                              color: _leftTabIndex == 1 ? const Color(0xFF9333EA) : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Variables',
                              style: TextStyle(
                                color: _leftTabIndex == 1 ? AppColors.textPrimary : AppColors.textSecondary,
                                fontWeight: _leftTabIndex == 1 ? FontWeight.bold : FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: _leftTabIndex == 1
                                    ? const Color(0xFF9333EA).withValues(alpha: 0.15)
                                    : AppColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${allVars.length}',
                                style: TextStyle(
                                  color: _leftTabIndex == 1 ? const Color(0xFF9333EA) : AppColors.textTertiary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Body: Tab 0 or Tab 1
          Expanded(
            child: _leftTabIndex == 0 ? _buildNodeLibraryTab() : _buildVariablesTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeLibraryTab() {
    final query = _nodeSearchQuery.trim().toLowerCase();

    final allCategories = _catalogCategories;
    final List<_PaletteItem> filteredItems = [];
    if (query.isNotEmpty) {
      for (final cat in allCategories) {
        final items = cat['items'] as List<_PaletteItem>;
        for (final item in items) {
          if (item.title.toLowerCase().contains(query) ||
              item.subtitle.toLowerCase().contains(query) ||
              item.type.toLowerCase().contains(query)) {
            filteredItems.add(item);
          }
        }
      }
    }

    return Column(
      children: [
        // Search Input
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: TextField(
            controller: _nodeSearchController,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
            onChanged: (val) => setState(() => _nodeSearchQuery = val),
            decoration: InputDecoration(
              hintText: 'Search blocks...',
              hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
              prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.textSecondary),
              suffixIcon: _nodeSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16, color: AppColors.textTertiary),
                      onPressed: () {
                        _nodeSearchController.clear();
                        setState(() => _nodeSearchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppColors.surfaceSunken,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
        ),

        // Node Catalog List
        Expanded(
          child: query.isNotEmpty
              ? (filteredItems.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.search_off_rounded, size: 36, color: AppColors.textTertiary),
                            const SizedBox(height: 8),
                            Text(
                              'No blocks matching "$query"',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                          child: Text(
                            'SEARCH RESULTS (${filteredItems.length})',
                            style: const TextStyle(color: AppColors.textTertiary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                          ),
                        ),
                        for (final item in filteredItems) _buildPaletteCard(item),
                      ],
                    ))
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                  children: [
                    for (final cat in allCategories)
                      _buildPaletteCategory(
                        cat['title'] as String,
                        cat['items'] as List<_PaletteItem>,
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildPaletteCategory(String title, List<_PaletteItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8),
          ),
        ),
        for (final item in items) _buildPaletteCard(item),
      ],
    );
  }

  Widget _buildPaletteCard(_PaletteItem item) {
    return InkWell(
      onTap: () => _addNodeFromCatalog(item.type),
      borderRadius: BorderRadius.circular(10),
      hoverColor: AppColors.surfaceSunken,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        margin: const EdgeInsets.symmetric(vertical: 2.5),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(item.icon, size: 16, color: item.color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                  Text(item.subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                ],
              ),
            ),
            const Icon(Icons.add_rounded, size: 18, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildVariablesTab() {
    final query = _variableSearchQuery.trim().toLowerCase();

    // 1. Initial Custom Variables
    final rawInitVars = _graph.initialVariables;
    final List<MapEntry<String, dynamic>> initVarEntries = rawInitVars.entries.where((e) {
      if (query.isEmpty) return true;
      return e.key.toLowerCase().contains(query);
    }).toList();

    // 2. Node Generated Variables
    final allNodeVars = _graph.getAllVariables().where((v) => !v.isSystem && v.sourceNodeId != null).toList();
    final filteredNodeVars = allNodeVars.where((v) {
      if (query.isEmpty) return true;
      return v.name.toLowerCase().contains(query) || v.source.toLowerCase().contains(query);
    }).toList();

    // 3. System Variables
    final allSysVars = _graph.getAllVariables().where((v) => v.isSystem).toList();
    final filteredSysVars = allSysVars.where((v) {
      if (query.isEmpty) return true;
      return v.name.toLowerCase().contains(query) || (v.description?.toLowerCase().contains(query) ?? false);
    }).toList();

    return Column(
      children: [
        // Action & Filter Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _variableSearchController,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                  onChanged: (val) => setState(() => _variableSearchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Filter variables...',
                    hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                    prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.textSecondary),
                    suffixIcon: _variableSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16, color: AppColors.textTertiary),
                            onPressed: () {
                              _variableSearchController.clear();
                              setState(() => _variableSearchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.surfaceSunken,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF9333EA),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  minimumSize: const Size(0, 36),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.buttonRadius)),
                ),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('New', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: () => _showAddEditVariableDialog(),
              ),
            ],
          ),
        ),

        // Variables Scrollable List
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
            children: [
              // SECTION 1: CUSTOM MISSION VARIABLES
              _buildVariableSectionHeader(
                icon: Icons.tune_rounded,
                title: 'MISSION VARIABLES',
                count: initVarEntries.length,
                color: const Color(0xFF9333EA),
                subtitle: 'Initial defaults configured for this mission',
                trailingAction: IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 18, color: Color(0xFF9333EA)),
                  tooltip: 'Add Mission Variable',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: () => _showAddEditVariableDialog(),
                ),
              ),
              if (initVarEntries.isEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSunken,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'No custom variables defined yet.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF9333EA),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                        icon: const Icon(Icons.add, size: 15),
                        label: const Text('Add Variable', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                        onPressed: () => _showAddEditVariableDialog(),
                      ),
                    ],
                  ),
                )
              else
                for (final entry in initVarEntries) _buildCustomVariableCard(entry),

              const SizedBox(height: 8),

              // SECTION 2: STEP OUTPUT VARIABLES
              _buildVariableSectionHeader(
                icon: Icons.alt_route_rounded,
                title: 'STEP OUTPUT VARIABLES',
                count: filteredNodeVars.length,
                color: const Color(0xFF0284C7),
                subtitle: 'Produced dynamically during execution',
              ),
              if (filteredNodeVars.isEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSunken,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'No step variables detected in graph.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF0284C7),
                          side: const BorderSide(color: Color(0xFF0284C7)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 14),
                        label: const Text('Add "Remember a Value" Block', style: TextStyle(fontSize: 11)),
                        onPressed: () => _addNodeFromCatalog('set_variable'),
                      ),
                    ],
                  ),
                )
              else
                for (final v in filteredNodeVars) _buildNodeVariableCard(v),

              const SizedBox(height: 8),

              // SECTION 3: SYSTEM TELEMETRY VARIABLES
              _buildVariableSectionHeader(
                icon: Icons.sensors_rounded,
                title: 'SYSTEM TELEMETRY',
                count: filteredSysVars.length,
                color: const Color(0xFF16A34A),
                subtitle: 'Automatic live robot state variables',
              ),
              for (final v in filteredSysVars) _buildSystemVariableCard(v),

              const SizedBox(height: 14),

              // SECTION 4: USAGE TIPS CARD
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline_rounded, size: 16, color: Color(0xFFEAB308)),
                        SizedBox(width: 6),
                        Text(
                          'HOW TO USE VARIABLES',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 10.5, fontWeight: FontWeight.bold, letterSpacing: 0.6),
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Wrap any variable name in curly braces to inject it into any field:\n'
                      '• Voice Speech: "Hello {guest_name}!"\n'
                      '• Screen Form: Room {target_room}\n'
                      '• Web URL: /status?batt={battery_pct}\n'
                      '• Condition: {battery_pct} < 20',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.45),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCustomVariableCard(MapEntry<String, dynamic> entry) {
    final key = entry.key;
    final val = entry.value;
    dynamic actualVal = val;
    String valType = 'string';
    String? desc;
    if (val is Map) {
      actualVal = val['value'] ?? val['default_value'] ?? '';
      valType = val['type']?.toString() ?? 'string';
      desc = val['description']?.toString();
    } else if (val is num) {
      valType = 'number';
    } else if (val is bool) {
      valType = 'boolean';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF9333EA).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '{$key}',
                  style: const TextStyle(
                    color: Color(0xFF9333EA),
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  valType.toUpperCase(),
                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 9.5, fontWeight: FontWeight.w700),
                ),
              ),
              const Spacer(),
              // Copy Button
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 15, color: AppColors.textSecondary),
                tooltip: 'Copy {$key}',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () => _copyVariableToClipboard(key),
              ),
              // Edit Button
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 15, color: AppColors.textSecondary),
                tooltip: 'Edit Variable',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () => _showAddEditVariableDialog(
                  initialKey: key,
                  initialValue: actualVal,
                  initialType: valType,
                  initialDesc: desc,
                ),
              ),
              // Delete Button
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 15, color: AppColors.danger),
                tooltip: 'Delete Variable',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () => _deleteVariable(key),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Value: ', style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
              Expanded(
                child: Text(
                  '$actualVal',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 11.5, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (desc != null && desc.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(desc, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5, fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }

  Widget _buildNodeVariableCard(AvailableVariable v) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '{${v.name}}',
                  style: const TextStyle(
                    color: Color(0xFF0284C7),
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              // Copy Button
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 15, color: AppColors.textSecondary),
                tooltip: 'Copy {${v.name}}',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () => _copyVariableToClipboard(v.name),
              ),
              // Focus Node on Canvas Button
              if (v.sourceNodeId != null)
                IconButton(
                  icon: const Icon(Icons.filter_center_focus_rounded, size: 15, color: AppColors.primary),
                  tooltip: 'Focus step on canvas',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => _focusNodeOnCanvas(v.sourceNodeId!),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.account_tree_outlined, size: 13, color: AppColors.textTertiary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  v.source,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSystemVariableCard(AvailableVariable v) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '{${v.name}}',
                    style: const TextStyle(
                      color: Color(0xFF16A34A),
                      fontSize: 11.5,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  v.description ?? v.source,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 15, color: AppColors.textSecondary),
            tooltip: 'Copy {${v.name}}',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => _copyVariableToClipboard(v.name),
          ),
        ],
      ),
    );
  }

  Widget _buildVariableSectionHeader({
    required IconData icon,
    required String title,
    required int count,
    required Color color,
    required String subtitle,
    Widget? trailingAction,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.bold, letterSpacing: 0.7),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.bold),
                ),
              ),
              const Spacer(),
              if (trailingAction != null) trailingAction,
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
          ),
        ],
      ),
    );
  }

  void _showAddEditVariableDialog({
    String? initialKey,
    dynamic initialValue,
    String? initialType,
    String? initialDesc,
  }) {
    final keyController = TextEditingController(text: initialKey ?? '');
    final valController = TextEditingController(text: initialValue != null ? '$initialValue' : '');
    final descController = TextEditingController(text: initialDesc ?? '');
    String selectedType = initialType ?? (initialValue is num ? 'number' : (initialValue is bool ? 'boolean' : 'string'));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              side: const BorderSide(color: AppColors.border),
            ),
            title: Row(
              children: [
                const Icon(Icons.data_object_rounded, color: Color(0xFF9333EA), size: 22),
                const SizedBox(width: 10),
                Text(
                  initialKey != null ? 'Edit Variable' : 'New Mission Variable',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Variable Name (Key)',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: keyController,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: 'e.g. guest_name, target_room, retry_count',
                      hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                      filled: true,
                      fillColor: AppColors.surfaceSunken,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  const Text(
                    'Data Type',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSunken,
                      borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: selectedType,
                        dropdownColor: AppColors.surface,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                        items: const [
                          DropdownMenuItem(value: 'string', child: Text('Text (String)')),
                          DropdownMenuItem(value: 'number', child: Text('Number (Integer / Decimal)')),
                          DropdownMenuItem(value: 'boolean', child: Text('Boolean (True / False)')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDlgState(() => selectedType = val);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  const Text(
                    'Default / Initial Value',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: valController,
                    keyboardType: selectedType == 'number' ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: selectedType == 'boolean' ? 'true or false' : (selectedType == 'number' ? '0' : 'Default text...'),
                      hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                      filled: true,
                      fillColor: AppColors.surfaceSunken,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  const Text(
                    'Description / Note (Optional)',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: descController,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'What is this variable used for?',
                      hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                      filled: true,
                      fillColor: AppColors.surfaceSunken,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF9333EA),
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  final key = keyController.text.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
                  if (key.isEmpty) return;

                  final rawVal = valController.text.trim();
                  dynamic parsedVal = rawVal;
                  if (selectedType == 'number') {
                    parsedVal = num.tryParse(rawVal) ?? 0;
                  } else if (selectedType == 'boolean') {
                    parsedVal = rawVal.toLowerCase() == 'true';
                  }

                  final vars = Map<String, dynamic>.from(_graph.initialVariables);
                  if (initialKey != null && initialKey != key) {
                    vars.remove(initialKey);
                  }
                  vars[key] = {
                    'value': parsedVal,
                    'type': selectedType,
                    'description': descController.text.trim(),
                  };

                  setState(() {
                    _graph.initialVariables = vars;
                  });
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Variable {$key} saved'),
                      backgroundColor: AppColors.success,
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: const Text('Save Variable'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _copyVariableToClipboard(String varName) {
    Clipboard.setData(ClipboardData(text: '{$varName}'));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied {$varName} to clipboard!'),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _deleteVariable(String key) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete Variable?', style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Text('Are you sure you want to delete variable "{$key}"? Steps referencing this variable might fail.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              Navigator.of(ctx).pop();
              final vars = Map<String, dynamic>.from(_graph.initialVariables);
              vars.remove(key);
              setState(() {
                _graph.initialVariables = vars;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Variable {$key} removed'), backgroundColor: AppColors.danger),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _focusNodeOnCanvas(String nodeId) {
    final target = _graph.nodes.where((n) => n.id == nodeId).firstOrNull;
    if (target != null) {
      setState(() {
        _selectedNode = target;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Focused on "${target.label.isNotEmpty ? target.label : target.id}"'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildRightSidebar(GraphNode? selectedNode) {
    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border, width: 1.0)),
      ),
      child: selectedNode != null
          ? Column(
              children: [
                Expanded(
                  child: MissionNodeInspector(
                    node: selectedNode,
                    graph: _graph,
                    onChanged: () => setState(() {}),
                    onDelete: () => _deleteNode(selectedNode),
                    availableMissions: _availableMissions,
                    api: _api,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceSunken,
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: const BorderSide(color: AppColors.danger),
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.buttonRadius)),
                          ),
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text('Delete Node', style: TextStyle(fontSize: 12)),
                          onPressed: () => _deleteNode(selectedNode),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Set as Entrypoint',
                        icon: Icon(
                          _graph.entrypoint == selectedNode.id ? Icons.flag : Icons.outlined_flag,
                          color: AppColors.primary,
                        ),
                        onPressed: () {
                          setState(() {
                            _graph.entrypoint = selectedNode.id;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ],
            )
          : (_selectedEdge != null ? _buildEdgeInspector(_selectedEdge!) : _buildGraphOverview()),
    );
  }

  Widget _buildEdgeInspector(GraphEdge edge) {
    final fromNode = _graph.nodes.firstWhere(
      (n) => n.id == edge.fromNode,
      orElse: () => GraphNode(id: edge.fromNode, type: 'unknown', position: Offset.zero),
    );
    final toNode = _graph.nodes.firstWhere(
      (n) => n.id == edge.toNode,
      orElse: () => GraphNode(id: edge.toNode, type: 'unknown', position: Offset.zero),
    );
    final fromName = fromNode.label.isNotEmpty ? fromNode.label : fromNode.id;
    final toName = toNode.label.isNotEmpty ? toNode.label : toNode.id;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.alt_route, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              const Text(
                'Connection Line',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
                tooltip: 'Deselect line',
                onPressed: () => setState(() => _selectedEdge = null),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SOURCE STEP (OUT)',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                const SizedBox(height: 4),
                Text(
                  fromName,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Port: ${edge.fromPort}',
                  style: const TextStyle(color: AppColors.primary, fontSize: 11),
                ),
                const SizedBox(height: 12),
                const Center(
                  child: Icon(Icons.south, size: 18, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                const Text(
                  'TARGET STEP (IN)',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                const SizedBox(height: 4),
                Text(
                  toName,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Port: ${edge.toPort}',
                  style: const TextStyle(color: AppColors.success, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (!_running)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.buttonRadius)),
                ),
                icon: const Icon(Icons.delete_forever, size: 18),
                label: const Text('Delete Connection Line'),
                onPressed: () {
                  setState(() {
                    _graph.edges.remove(edge);
                    _selectedEdge = null;
                  });
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGraphOverview() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('MISSION OVERVIEW', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.6)),
          const SizedBox(height: 16),

          _buildStatCard('Total Nodes', '${_graph.nodes.length}', Icons.grid_view),
          const SizedBox(height: 8),
          _buildStatCard('Total Connections', '${_graph.edges.length}', Icons.alt_route),
          const SizedBox(height: 16),

          const Text('Entrypoint Node', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Builder(
            builder: (context) {
              final nodeIds = _graph.nodes.map((n) => n.id).toSet();
              final validEntrypoint = nodeIds.contains(_graph.entrypoint)
                  ? _graph.entrypoint
                  : (_graph.nodes.isNotEmpty ? _graph.nodes.first.id : null);
              if (_graph.entrypoint != validEntrypoint && validEntrypoint != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _graph.entrypoint != validEntrypoint) {
                    setState(() => _graph.entrypoint = validEntrypoint);
                  }
                });
              }

              return DropdownButtonFormField<String>(
                key: ValueKey('entrypoint_${validEntrypoint}_${_graph.nodes.length}'),
                isExpanded: true,
                initialValue: validEntrypoint,
                dropdownColor: AppColors.surface,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.surfaceSunken,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                ),
                hint: const Text('No entrypoint selected', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                items: [
                  for (final n in _graph.nodes)
                    DropdownMenuItem(
                      value: n.id,
                      child: Text(
                        '${n.label} (${n.id})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _graph.entrypoint = v),
              );
            },
          ),
          const SizedBox(height: 20),

          const Divider(color: AppColors.border),
          const SizedBox(height: 10),
          const Text('TIPS', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.6)),
          const SizedBox(height: 8),
          const Text(
            '• Drag from any output port circle to an input port circle to create a connection wire.\n'
            '• Click on any connection wire to delete it.\n'
            '• Pan the canvas using mouse drag or scroll wheel.\n'
            '• Use the Node Library on the left to add new action blocks.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const Spacer(),
          Text(value, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }
}

class _PaletteItem {
  const _PaletteItem(this.type, this.title, this.subtitle, this.icon, this.color);
  final String type;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
}
