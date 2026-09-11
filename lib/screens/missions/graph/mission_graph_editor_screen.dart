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

  GraphNode? _selectedNode;
  String? _activeNodeId;
  String? _missionState; // idle, running, waiting_for_user, paused, completed, failed
  String? _currentMap;
  List<String> _availableMaps = [];
  bool _saving = false;
  bool _running = false;
  bool _isModalShowing = false;
  Map<String, dynamic>? _activeRobotInteraction;

  Timer? _statusPoller;

  SdkApiService? get _api {
    final ip = context.read<ConnectionProvider>().robot?.ip;
    return ip == null ? null : SdkApiService(ip);
  }

  @override
  void initState() {
    super.initState();
    _initGraph();
    _nameController = TextEditingController(text: _graph.name);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
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
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final api = _api;
    if (api == null) return;

    try {
      final maps = await api.listMaps();
      final active = await api.getCurrentMap();
      final wps = await api.listWaypoints();
      LocationsController.instance.value = wps;

      if (mounted) {
        setState(() {
          _availableMaps = maps;
          _currentMap = active;
          _graph.map ??= active;
        });
      }
    } catch (_) {}
  }

  void _startExecutionPolling() {
    _statusPoller?.cancel();
    _statusPoller = Timer.periodic(const Duration(milliseconds: 600), (t) async {
      final api = _api;
      if (api == null || !mounted) return;

      try {
        final status = await api.missionStatus();
        final state = status['state']?.toString() ?? 'idle';
        final activeNode = status['active_node_id']?.toString();

        if (mounted) {
          setState(() {
            _missionState = state;
            _activeNodeId = activeNode;
            _running = (state == 'running' || state == 'waiting_for_user' || state == 'paused');
          });
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
    final errors = _validateGraph();
    if (errors.isNotEmpty) {
      _showValidationDialog(errors);
      return;
    }

    // Save first then execute
    await _saveMission();

    try {
      await api.startMission(_graph.id);
      setState(() {
        _running = true;
        _missionState = 'running';
      });
      _startExecutionPolling();
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

  List<String> _validateGraph() {
    final errors = <String>[];
    if (_graph.nodes.isEmpty) {
      errors.add('The graph contains no nodes.');
      return errors;
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

    return errors;
  }

  void _showValidationDialog(List<String> errors) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B202C),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            SizedBox(width: 8),
            Text('Validation Warnings', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final err in errors)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• $err', style: const TextStyle(color: Color(0xFFCFD8DC), fontSize: 13)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK', style: TextStyle(color: Color(0xFF00E5FF))),
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
        defaultLabel = 'Mission Start';
        break;
      case 'end':
      case 'mission_end':
        defaultLabel = 'Mission End';
        defaultParams = {'status': 'success', 'message': 'Mission completed successfully.', 'dock_on_end': false};
        break;
      case 'loop':
      case 'loop_counter':
        defaultLabel = 'Loop / Repeat';
        defaultParams = {'count': 3, 'variable_name': 'loop_index', 'max_iterations': 50};
        break;
      case 'battery_guard':
        defaultLabel = 'Battery Guard';
        defaultParams = {'min_battery_pct': 20.0, 'require_charging': false};
        break;
      case 'patrol_loop':
        defaultLabel = 'Patrol Loop';
        defaultParams = {'waypoints': <String>[], 'laps': 1, 'dwell_sec': 2.0};
        break;
      case 'navigate_waypoint':
        defaultLabel = 'Go to Waypoint';
        defaultParams = {'waypoint': '', 'tolerance_m': 0.25};
        break;
      case 'navigate_coordinates':
        defaultLabel = 'Go to Coordinates';
        defaultParams = {'x': 0.0, 'y': 0.0, 'theta': 0.0, 'tolerance_m': 0.25};
        break;
      case 'dock':
        defaultLabel = 'Dock to Charger';
        defaultParams = {'timeout_sec': 60.0};
        break;
      case 'undock':
        defaultLabel = 'Undock Robot';
        break;
      case 'wait':
        defaultLabel = 'Wait / Delay';
        defaultParams = {'duration': 5.0};
        break;
      case 'condition':
        defaultLabel = 'If Condition';
        defaultParams = {'expression': "form['status'] == 'Pass'"};
        break;
      case 'ui_interaction':
        defaultLabel = 'Operator Form / UI';
        defaultParams = {
          'target': 'robot_screen',
          'subtype': 'dynamic_form',
          'title': 'Inspection Checklist',
          'message': 'Please complete the field checklist before proceeding.',
          'timeout_sec': 60.0,
          'fields': [
            {'key': 'inspector_name', 'label': 'Inspector Name', 'type': 'text', 'required': true},
            {'key': 'status', 'label': 'Status', 'type': 'select', 'options': ['Pass', 'Fail']},
          ],
        };
        break;
      case 'ui_media':
        defaultLabel = 'Multimedia Player';
        defaultParams = {
          'media_type': 'image',
          'url': 'https://images.unsplash.com/photo-1485827404703-89b55fcc595e',
          'duration_sec': 15.0,
          'show_skip': true,
          'target': 'robot_screen',
        };
        break;
      case 'ui_speech':
        defaultLabel = 'Voice Announcement';
        defaultParams = {'text': 'NavPro Mini has arrived at your station.', 'wait_completion': true};
        break;
      case 'call_api':
        defaultLabel = 'Webhook / HTTP';
        defaultParams = {'method': 'POST', 'url': 'https://api.example.com/log', 'timeout_sec': 10.0};
        break;
      case 'notify':
        defaultLabel = 'OLED / LED Signal';
        defaultParams = {'line1': 'Station Arrived', 'line2': 'Status OK', 'led_color': '#00E5FF'};
        break;
      case 'set_variable':
        defaultLabel = 'Set Context Variable';
        defaultParams = {'key': 'inspected', 'value': true};
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: Row(
        children: [
          // Left Palette
          _buildNodePalette(),

          // Center Graph Canvas with robot interaction banner
          Expanded(
            child: Column(
              children: [
                if (_activeRobotInteraction != null)
                  _buildRobotInteractionBanner(),
                Expanded(
                  child: MissionGraphCanvas(
                    graph: _graph,
                    selectedNode: _selectedNode,
                    activeNodeId: _activeNodeId,
                    onSelectNode: (node) => setState(() => _selectedNode = node),
                    onGraphChanged: () => setState(() {}),
                  ),
                ),
              ],
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
          const SizedBox(width: 12),
          SizedBox(
            width: 220,
            child: TextField(
              controller: _nameController,
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Mission Name',
                hintStyle: TextStyle(color: AppColors.textTertiary),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Map Selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
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
            final errs = _validateGraph();
            if (errs.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Graph structure is valid!'), backgroundColor: AppColors.success),
              );
            } else {
              _showValidationDialog(errs);
            }
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

  Widget _buildNodePalette() {
    return Container(
      width: 250,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border, width: 1.0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: const Row(
              children: [
                Icon(Icons.widgets_outlined, size: 18, color: AppColors.primary),
                SizedBox(width: 8),
                Text(
                  'NODE LIBRARY',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              children: [
                _buildPaletteCategory('Navigation & Motion', [
                  _PaletteItem('navigate_waypoint', 'Waypoint Goal', 'Go to named waypoint', Icons.place_outlined, const Color(0xFF2563EB)),
                  _PaletteItem('navigate_coordinates', 'Coordinates Goal', 'Go to (x, y, theta)', Icons.navigation_outlined, const Color(0xFF0284C7)),
                  _PaletteItem('patrol_loop', 'Patrol Loop', 'Multi-point perimeter patrol', Icons.sync_rounded, const Color(0xFF3B82F6)),
                  _PaletteItem('dock', 'Dock to Charger', 'Auto-align to dock', Icons.battery_charging_full, const Color(0xFF16A34A)),
                  _PaletteItem('undock', 'Undock Robot', 'Back out of charger', Icons.power_settings_new, const Color(0xFF059669)),
                ]),
                _buildPaletteCategory('Control Flow & Logic', [
                  _PaletteItem('end', 'Mission End', 'Clean terminal completion', Icons.stop_circle_outlined, const Color(0xFFDC2626)),
                  _PaletteItem('loop', 'Loop / Repeat', 'Iterate sub-branch N times', Icons.loop_rounded, const Color(0xFF7C3AED)),
                  _PaletteItem('condition', 'Conditional Branch', 'If-else AST evaluation', Icons.alt_route, const Color(0xFFEA580C)),
                  _PaletteItem('wait', 'Timer / Delay', 'Wait specified seconds', Icons.timer_outlined, const Color(0xFFD97706)),
                  _PaletteItem('battery_guard', 'Battery Guard', 'Energy threshold check', Icons.battery_saver, const Color(0xFF059669)),
                  _PaletteItem('set_variable', 'Set Context Var', 'Blackboard state store', Icons.data_object, const Color(0xFF9333EA)),
                ]),
                _buildPaletteCategory('HRI & Interaction', [
                  _PaletteItem('ui_interaction', 'Operator Form / UI', 'Human-in-the-loop modal', Icons.touch_app_outlined, AppColors.primary),
                  _PaletteItem('ui_media', 'Multimedia Player', 'Display photo, video or web', Icons.perm_media_outlined, const Color(0xFF0284C7)),
                  _PaletteItem('ui_speech', 'Voice Announcement', 'Text-to-speech speaker', Icons.record_voice_over_outlined, const Color(0xFF8B5CF6)),
                  _PaletteItem('notify', 'OLED & LED Signals', 'Show screen lines & LEDs', Icons.tv, const Color(0xFF0D9488)),
                ]),
                _buildPaletteCategory('Integrations & Actions', [
                  _PaletteItem('call_api', 'Webhook / HTTP', 'REST API trigger', Icons.http, const Color(0xFF7C3AED)),
                  _PaletteItem('call_service', 'ROS 2 Service', 'Trigger service call', Icons.settings_remote, const Color(0xFF4F46E5)),
                  _PaletteItem('call_action', 'ROS 2 Action', 'Trigger action client', Icons.bolt, const Color(0xFF0284C7)),
                ]),
              ],
            ),
          ),
        ],
      ),
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
        for (final item in items)
          InkWell(
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
          ),
      ],
    );
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
                    onChanged: () => setState(() {}),
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
                          onPressed: () {
                            setState(() {
                              _graph.nodes.removeWhere((n) => n.id == selectedNode.id);
                              _graph.edges.removeWhere((e) => e.fromNode == selectedNode.id || e.toNode == selectedNode.id);
                              if (_graph.entrypoint == selectedNode.id) {
                                _graph.entrypoint = _graph.nodes.isNotEmpty ? _graph.nodes.first.id : null;
                              }
                              _selectedNode = null;
                            });
                          },
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
          : _buildGraphOverview(),
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
