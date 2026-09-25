import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../services/locations_controller.dart';
import '../../../services/sdk_api_service.dart';
import '../../../theme/app_theme.dart';
import 'mission_graph_models.dart';

/// Contextual Properties Inspector & Dynamic Form Builder for the selected node.
class MissionNodeInspector extends StatefulWidget {
  const MissionNodeInspector({
    super.key,
    required this.node,
    required this.onChanged,
    this.graph,
    this.onDelete,
    this.readOnly = false,
    this.availableMissions = const [],
    this.api,
  });

  final GraphNode node;
  final MissionGraph? graph;
  final VoidCallback onChanged;
  final VoidCallback? onDelete;
  final bool readOnly;
  final List<Map<String, dynamic>> availableMissions;
  final SdkApiService? api;

  @override
  State<MissionNodeInspector> createState() => _MissionNodeInspectorState();
}

class _MissionNodeInspectorState extends State<MissionNodeInspector>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _labelController;
  late FocusNode _labelFocusNode;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _labelController = TextEditingController(text: widget.node.label);
    _labelFocusNode = FocusNode();
  }

  void _setActiveField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required ValueChanged<String> onChanged,
  }) {}



  List<AvailableVariable> _getAvailableVariables() {
    if (widget.graph != null) {
      return widget.graph!.getAllVariables();
    }
    // Fallback if graph instance not provided
    final mockGraph = MissionGraph(id: 'temp', name: 'temp', nodes: [widget.node]);
    return mockGraph.getAllVariables();
  }



  Widget _buildVariableInputField({
    required String label,
    required String initialValue,
    required ValueChanged<String> onChanged,
    String? hintText,
    String? helperText,
    int maxLines = 1,
    TextInputType? keyboardType,
    Widget? prefixIcon,
  }) {
    return _VariableAwareTextField(
      key: ValueKey('${widget.node.id}_$label'),
      labelText: label,
      initialValue: initialValue,
      hintText: hintText,
      helperText: helperText,
      maxLines: maxLines,
      keyboardType: keyboardType,
      prefixIcon: prefixIcon,
      enabled: !widget.readOnly,
      availableVariables: _getAvailableVariables(),
      onFocus: (controller, focusNode, changeCb) {
        _setActiveField(
          controller: controller,
          focusNode: focusNode,
          onChanged: changeCb,
        );
      },
      onChanged: onChanged,
    );
  }

  @override
  void didUpdateWidget(covariant MissionNodeInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) {
      _labelController.text = widget.node.label;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _labelController.dispose();
    _labelFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final isUiInteraction = node.type == 'ui_interaction';

    return Container(
      width: 320,
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Builder(
                  builder: (context) {
                    final (headerIcon, headerColor) = _getNodeHeaderMeta(node);
                    return Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: headerColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: headerColor.withValues(alpha: 0.3), width: 1.0),
                      ),
                      child: Icon(headerIcon, size: 18, color: headerColor),
                    );
                  },
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _getNodeFriendlyTitle(node),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Step Settings',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!widget.readOnly)
                  IconButton(
                    icon: const Icon(Icons.rotate_right_rounded, color: AppColors.primary, size: 20),
                    tooltip: 'Rotate Connection Points (Press R to cycle 90°)',
                    onPressed: () {
                      node.rotationDegrees = (node.rotationDegrees + 90) % 360;
                      widget.onChanged();
                    },
                  ),
                if (widget.onDelete != null && node.type != 'start' && !widget.readOnly)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                    tooltip: 'Delete this step',
                    onPressed: widget.onDelete,
                  ),
              ],
            ),
          ),


          // Tabs (Properties vs Preview for UI interaction)
          if (isUiInteraction)
            TabBar(
              controller: _tabController,
              indicatorColor: AppColors.primary,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              tabs: const [
                Tab(text: 'Settings'),
                Tab(text: 'Screen Preview'),
              ],
            ),

          // Body
          Expanded(
            child: isUiInteraction
                ? TabBarView(
                    controller: _tabController,
                    children: [
                      _buildPropertiesList(),
                      _buildLiveFormPreview(),
                    ],
                  )
                : _buildPropertiesList(),
          ),
        ],
      ),
    );
  }

  (IconData, Color) _getNodeHeaderMeta(GraphNode node) {
    final status = (node.params['status'] as String? ?? '').toLowerCase();
    final isAborted = node.type == 'abort' ||
        node.type == 'abort_and_end' ||
        status == 'failed' ||
        status == 'aborted';
    if (isAborted) return (Icons.stop_rounded, const Color(0xFFEF4444));
    if (node.type == 'dock_and_end' || node.params['dock_on_end'] == true) {
      return (Icons.charging_station_rounded, const Color(0xFF10B981));
    }
    switch (node.type) {
      case 'start':
        return (Icons.play_arrow_rounded, AppColors.success);
      case 'end':
      case 'mission_end':
        return (Icons.task_alt_rounded, const Color(0xFF0D9488));
      case 'navigate_waypoint':
        return (Icons.navigation_rounded, const Color(0xFF2563EB));
      case 'navigate_coordinates':
        return (Icons.explore_rounded, const Color(0xFF2563EB));
      case 'patrol_loop':
        return (Icons.sync_rounded, const Color(0xFF3B82F6));
      case 'relocalize':
        return (Icons.my_location_rounded, const Color(0xFF0284C7));
      case 'cancel_navigation':
        return (Icons.cancel_rounded, const Color(0xFFDC2626));
      case 'wait':
        return (Icons.timer_outlined, const Color(0xFFD97706));
      case 'dock':
        return (Icons.charging_station_rounded, const Color(0xFF16A34A));
      case 'undock':
        return (Icons.power_settings_new_rounded, const Color(0xFF059669));
      case 'jog_motion':
        return (Icons.gamepad_outlined, const Color(0xFFD97706));
      case 'emergency_stop':
        return (Icons.emergency_rounded, const Color(0xFFDC2626));
      case 'loop':
      case 'loop_counter':
        return (Icons.loop_rounded, const Color(0xFF7C3AED));
      case 'condition':
        return (Icons.alt_route_rounded, const Color(0xFFEA580C));
      case 'parallel':
      case 'parallel_fork':
        return (Icons.call_split_rounded, const Color(0xFF00ACC1));
      case 'battery_guard':
        return (Icons.battery_saver_rounded, const Color(0xFF059669));
      case 'set_variable':
        return (Icons.data_object_rounded, const Color(0xFF9333EA));
      case 'ui_interaction':
        return (Icons.touch_app_rounded, AppColors.primary);
      case 'ui_notification':
        return (Icons.notifications_active_rounded, const Color(0xFF0284C7));
      case 'ui_choice':
        return (Icons.ads_click_rounded, AppColors.primary);
      case 'ui_media':
        return (Icons.smart_display_rounded, const Color(0xFF0284C7));
      case 'ui_speech':
        return (Icons.record_voice_over_rounded, const Color(0xFF8B5CF6));
      case 'notify':
        return (Icons.lightbulb_rounded, const Color(0xFF0D9488));
      case 'call_api':
        return (Icons.http_rounded, const Color(0xFF7C3AED));
      case 'call_service':
        return (Icons.precision_manufacturing_rounded, const Color(0xFF4F46E5));
      case 'call_action':
        return (Icons.settings_input_component_rounded, const Color(0xFF4F46E5));
      case 'publish_topic':
        return (Icons.podcasts_rounded, const Color(0xFF4F46E5));
      case 'switch_mission':
      case 'redirect_mission':
        return (Icons.shuffle_rounded, const Color(0xFF009688));
      default:
        return (Icons.tune, AppColors.primary);
    }
  }

  String _getNodeFriendlyTitle(GraphNode node) {
    if (node.label.isNotEmpty) return node.label;
    switch (node.type) {
      case 'start':
        return 'Mission Start & Triggers';
      case 'end':
      case 'mission_end':
      case 'dock_and_end':
      case 'abort':
      case 'abort_and_end':
        final isAborted = node.type == 'abort' ||
            node.type == 'abort_and_end' ||
            (node.params['status'] as String? ?? '').toLowerCase() == 'failed' ||
            (node.params['status'] as String? ?? '').toLowerCase() == 'aborted';
        if (isAborted) return 'Abort / Halt Mission';
        if (node.type == 'dock_and_end' || node.params['dock_on_end'] == true) return 'Dock & Finish Mission';
        return 'Finish Mission';
      case 'navigate_waypoint':
        return 'Drive to Saved Place';
      case 'navigate_coordinates':
        return 'Drive to Coordinates';
      case 'patrol_loop':
        return 'Patrol Route';
      case 'relocalize':
        return 'Find My Position';
      case 'cancel_navigation':
        return 'Stop Driving';
      case 'dock':
        return 'Go to Charger';
      case 'undock':
        return 'Leave Charger';
      case 'jog_motion':
        return 'Nudge / Turn Wheels';
      case 'emergency_stop':
        return 'Safety Emergency Stop';
      case 'loop':
      case 'loop_counter':
        return 'Repeat Steps';
      case 'parallel':
      case 'parallel_fork':
        return 'Run in Parallel';
      case 'condition':
        return 'Check / If-Else';
      case 'wait':
        return 'Pause & Wait';
      case 'battery_guard':
        return 'Check Battery Level';
      case 'set_variable':
        return 'Remember a Value';
      case 'ui_interaction':
        return 'Ask for Information';
      case 'ui_notification':
        return 'Show Notification';
      case 'ui_choice':
        return 'Ask Choice (Buttons)';
      case 'ui_media':
        return 'Show Picture / Video';
      case 'ui_speech':
        return 'Speak Aloud';
      case 'notify':
        return 'Lights & Chime Signal';
      case 'call_api':
        return 'Send Web Notice';
      case 'call_service':
        return 'Trigger Robot Tool';
      case 'call_action':
        return 'Run Background Task';
      case 'publish_topic':
        return 'Broadcast Signal';
      case 'switch_mission':
      case 'redirect_mission':
        return 'Switch Mission (Handoff)';
      default:
        return 'Step Settings';
    }
  }

  String _getNodeFriendlyDescription(GraphNode node) {
    switch (node.type) {
      case 'start':
        return 'Where your workflow begins. Configure trigger mode: manual on-demand, repeating interval (every X minutes), or clock alarm (specific time & days).';
      case 'end':
      case 'mission_end':
      case 'dock_and_end':
      case 'abort':
      case 'abort_and_end':
        final isAb = node.type == 'abort' ||
            node.type == 'abort_and_end' ||
            (node.params['status'] as String? ?? '').toLowerCase() == 'failed' ||
            (node.params['status'] as String? ?? '').toLowerCase() == 'aborted';
        if (isAb) return 'Immediately stops and halts the workflow with an aborted/error outcome.';
        return 'Safely finishes the mission. The robot stops and can optionally drive back to its charger.';
      case 'navigate_waypoint':
        return 'Tells the robot to safely drive across the room to a place saved on your map.';
      case 'navigate_coordinates':
        return 'Sends the robot to a precise X and Y position on the map, facing a specific direction.';
      case 'patrol_loop':
        return 'Guides the robot through multiple saved places in sequence, pausing at each stop.';
      case 'relocalize':
        return 'Performs a 360° laser scan to help the robot figure out exactly where it is in the building.';
      case 'cancel_navigation':
        return 'Immediately cancels current driving and brings the robot to a complete halt.';
      case 'dock':
        return 'Drives the robot onto its charging station and begins recharging.';
      case 'undock':
        return 'Safely backs out of the charging dock so the robot is ready to start driving.';
      case 'jog_motion':
        return 'Directly nudges the wheels forward, backward, or turns the robot for a brief duration.';
      case 'emergency_stop':
        return 'Immediately cuts power to all drive motors and sounds a safety alert.';
      case 'loop':
      case 'loop_counter':
        return 'Repeats the connected steps multiple times (e.g. patrol a loop 3 times) before finishing.';
      case 'parallel':
      case 'parallel_fork':
        return 'Splits the workflow into concurrent branches that execute simultaneously (e.g. speak speech while presenting screen form).';
      case 'condition':
        return 'Makes a decision. If your rule is met, take the Yes path; otherwise take the No path.';
      case 'wait':
        return 'Pauses and waits for a few seconds before continuing to the next step.';
      case 'battery_guard':
        return 'Checks if the battery has enough charge. If it is low, you can route the robot to recharge.';
      case 'set_variable':
        return 'Saves a piece of information, number, or counter to use in later steps.';
      case 'ui_notification':
        return 'Displays a notification card with Title, Description, and an OK button on the robot screen.';
      case 'ui_interaction':
        return 'Displays a friendly form or checklist on the robot screen for a person to fill out.';
      case 'ui_choice':
        return 'Shows large touch buttons on the robot screen (like Yes or No) for someone to tap.';
      case 'ui_media':
        return 'Shows an image, diagram, or video on the robot screen for people nearby.';
      case 'ui_speech':
        return 'Reads a message out loud through the robot speakers in clear voice.';
      case 'notify':
        return 'Flashes the LED lights and sounds a chime to get attention.';
      case 'call_api':
        return 'Sends a notification or data over the network to a website or app like Slack.';
      case 'call_service':
        return 'Triggers a built-in robot hardware tool or toggles an internal setting.';
      case 'call_action':
        return 'Starts a longer robot activity and waits for it to complete.';
      case 'publish_topic':
        return 'Broadcasts a live message to other parts of the robot system.';
      case 'switch_mission':
      case 'redirect_mission':
        return 'Hands off execution to another mission on the same map.';
      default:
        return 'Configure the settings for this mission step.';
    }
  }

  Widget _buildPropertiesList() {
    final node = widget.node;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Friendly Explanatory Tip Box for End-Users
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lightbulb_outline, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _getNodeFriendlyDescription(node),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Node Label
        TextField(
          controller: _labelController,
          focusNode: _labelFocusNode,
          enabled: !widget.readOnly,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          onTap: () {
            _setActiveField(
              controller: _labelController,
              focusNode: _labelFocusNode,
              onChanged: (val) {
                node.label = val;
                widget.onChanged();
              },
            );
          },
          decoration: InputDecoration(
            labelText: 'Step Name (Shown on Canvas)',
            hintText: 'e.g. Drive to Charging Station',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          onChanged: (val) {
            node.label = val;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 16),

        // Type specific inspectors
        if (node.type == 'start')
          _buildStartInspector()
        else if (node.type == 'navigate_waypoint')
          _buildNavigateWaypointInspector()
        else if (node.type == 'navigate_coordinates')
          _buildNavigateCoordinatesInspector()
        else if (node.type == 'wait')
          _buildWaitInspector()
        else if (node.type == 'condition')
          _buildConditionInspector()
        else if (node.type == 'call_api')
          _buildCallApiInspector()
        else if (node.type == 'ui_interaction')
          _buildUiInteractionInspector()
        else if (node.type == 'ui_notification')
          _buildUiNotificationInspector()
        else if (node.type == 'ui_choice')
          _buildUiChoiceInspector()
        else if (node.type == 'set_variable')
          _buildSetVariableInspector()
        else if (node.type == 'notify')
          _buildNotifyInspector()
        else if (node.type == 'end' ||
            node.type == 'mission_end' ||
            node.type == 'dock_and_end' ||
            node.type == 'abort' ||
            node.type == 'abort_and_end')
          _buildEndMissionInspector()
        else if (node.type == 'loop' || node.type == 'loop_counter')
          _buildLoopInspector()
        else if (node.type == 'parallel' || node.type == 'parallel_fork')
          _buildParallelInspector()
        else if (node.type == 'battery_guard')
          _buildBatteryGuardInspector()
        else if (node.type == 'patrol_loop')
          _buildPatrolLoopInspector()
        else if (node.type == 'ui_media')
          _buildUiMediaInspector()
        else if (node.type == 'ui_speech')
          _buildUiSpeechInspector()
        else if (node.type == 'call_service')
          _buildCallServiceInspector()
        else if (node.type == 'call_action')
          _buildCallActionInspector()
        else if (node.type == 'publish_topic')
          _buildPublishTopicInspector()
        else if (node.type == 'relocalize')
          _buildRelocalizeInspector()
        else if (node.type == 'jog_motion')
          _buildJogMotionInspector()
        else if (node.type == 'emergency_stop')
          _buildEmergencyStopInspector()
        else if (node.type == 'cancel_navigation')
          _buildCancelNavigationInspector()
        else if (node.type == 'switch_mission' || node.type == 'redirect_mission')
          _buildSwitchMissionInspector()
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_outline, size: 18, color: AppColors.primary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This step is ready! No extra settings needed.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

        // Connected Lines Section
        _buildConnectedLinesSection(node),
      ],
    );
  }

  Widget _buildConnectedLinesSection(GraphNode node) {
    if (widget.graph == null) return const SizedBox.shrink();

    final incoming = widget.graph!.edges.where((e) => e.toNode == node.id).toList();
    final outgoing = widget.graph!.edges.where((e) => e.fromNode == node.id).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Divider(color: AppColors.border),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.hub_outlined, size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text(
              'Connected Lines',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                '${incoming.length + outgoing.length}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (incoming.isEmpty && outgoing.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              children: [
                Icon(Icons.link_off, size: 16, color: AppColors.textTertiary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No lines connected to this step. Drag from an output port or tap a line to connect.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  ),
                ),
              ],
            ),
          )
        else ...[
          if (incoming.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 6),
              child: Text(
                'INCOMING (Inputs)',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ),
            for (final edge in incoming)
              _buildEdgeTile(edge, isIncoming: true),
          ],
          if (outgoing.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 6),
              child: Text(
                'OUTGOING (Outputs)',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ),
            for (final edge in outgoing)
              _buildEdgeTile(edge, isIncoming: false),
          ],
        ],
      ],
    );
  }

  Widget _buildEdgeTile(GraphEdge edge, {required bool isIncoming}) {
    final otherNodeId = isIncoming ? edge.fromNode : edge.toNode;
    final otherNode = widget.graph?.nodes.firstWhere(
      (n) => n.id == otherNodeId,
      orElse: () => GraphNode(id: otherNodeId, type: 'unknown', position: Offset.zero),
    );
    final otherName = (otherNode != null && otherNode.label.isNotEmpty)
        ? otherNode.label
        : (otherNode != null ? _getNodeFriendlyTitle(otherNode) : otherNodeId);

    final portName = isIncoming ? edge.toPort : edge.fromPort;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Icon(
            isIncoming ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded,
            size: 15,
            color: isIncoming ? AppColors.primary : AppColors.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isIncoming ? 'From "$otherName"' : 'To "$otherName"',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  isIncoming ? 'Port: $portName (In)' : 'Port: $portName (Out)',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          if (!widget.readOnly)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
              tooltip: 'Delete connection line',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () {
                setState(() {
                  widget.graph?.edges.remove(edge);
                });
                widget.onChanged();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildNavigateWaypointInspector() {
    final waypoints = LocationsController.instance.value ?? const <Map<String, dynamic>>[];
    final currentWp = widget.node.params['waypoint'] as String?;

    // Collect all dynamic variables from UI form nodes and variable nodes in this mission graph
    final dynamicVariables = <String>{};
    for (final n in widget.graph?.nodes ?? const <GraphNode>[]) {
      if (n.type == 'ui_interaction') {
        final fields = n.params['fields'] as List? ?? [];
        for (final f in fields) {
          if (f is Map && f['key'] != null && f['key'].toString().isNotEmpty) {
            dynamicVariables.add('{${f['key']}}');
          }
        }
      } else if (n.type == 'set_variable') {
        final key = n.params['key'] ?? n.params['name'] ?? n.params['variable'];
        if (key != null && key.toString().isNotEmpty) {
          dynamicVariables.add('{$key}');
        }
      }
    }

    final isCustomVariable = currentWp != null && currentWp.startsWith('{') && currentWp.endsWith('}');
    final allKnownValues = {
      for (final wp in waypoints) wp['name']?.toString() ?? '',
      ...dynamicVariables,
      if (currentWp != null && currentWp.isNotEmpty) currentWp,
    }..remove('');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Where should the robot drive?', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: ValueKey('${widget.node.id}_wp_$currentWp'),
          isExpanded: true,
          initialValue: allKnownValues.contains(currentWp) ? currentWp : null,
          dropdownColor: AppColors.surfaceElevated,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          hint: const Text('Choose a saved place or form variable', style: TextStyle(color: AppColors.textSecondary)),
          items: [
            if (waypoints.isNotEmpty) ...[
              for (final wp in waypoints)
                DropdownMenuItem(
                  value: wp['name']?.toString() ?? '',
                  child: Row(
                    children: [
                      const Icon(Icons.place_rounded, size: 14, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${wp['name']} (x: ${(wp['x'] as num?)?.toStringAsFixed(1) ?? '0.0'}, y: ${(wp['y'] as num?)?.toStringAsFixed(1) ?? '0.0'})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (dynamicVariables.isNotEmpty) ...[
              for (final v in dynamicVariables)
                DropdownMenuItem(
                  value: v,
                  child: Row(
                    children: [
                      const Icon(Icons.input_rounded, size: 14, color: Color(0xFF8B5CF6)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'User Selected: $v (From Form)',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (isCustomVariable && !dynamicVariables.contains(currentWp))
              DropdownMenuItem(
                value: currentWp,
                child: Row(
                  children: [
                    const Icon(Icons.code_rounded, size: 14, color: Color(0xFF8B5CF6)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Variable: $currentWp',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          onChanged: widget.readOnly
              ? null
              : (val) {
                  setState(() {
                    widget.node.params['waypoint'] = val;
                  });
                  widget.onChanged();
                },
        ),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: currentWp ?? '',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
          decoration: InputDecoration(
            isDense: true,
            labelText: 'Or type custom location / variable name',
            hintText: 'e.g. Kitchen or {field_1}',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
            prefixIcon: const Icon(Icons.edit_note_rounded, size: 16),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          onChanged: widget.readOnly
              ? null
              : (v) {
                  widget.node.params['waypoint'] = v.trim();
                  widget.onChanged();
                },
        ),
        const SizedBox(height: 4),
        const Text(
          '💡 Tip: Type a variable like {field_1} to navigate to the location chosen by the user in an earlier form step.',
          style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
        ),
        const SizedBox(height: 16),
        _buildNumberSlider(
          label: 'Arrival accuracy (meters)',
          value: (widget.node.params['tolerance_m'] as num?)?.toDouble() ?? 0.25,
          min: 0.05,
          max: 1.0,
          divisions: 19,
          onChanged: (v) {
            widget.node.params['tolerance_m'] = v;
            widget.onChanged();
          },
        ),
      ],
    );
  }

  Widget _buildNavigateCoordinatesInspector() {
    final x = (widget.node.params['x'] as num?)?.toDouble() ?? 0.0;
    final y = (widget.node.params['y'] as num?)?.toDouble() ?? 0.0;
    final theta = (widget.node.params['theta'] as num?)?.toDouble() ?? 0.0;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                initialValue: x.toString(),
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  labelText: 'X Position on Map (meters)',
                  labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  filled: true,
                  fillColor: AppColors.surfaceSunken,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                ),
                onChanged: (v) {
                  widget.node.params['x'] = double.tryParse(v) ?? 0.0;
                  widget.onChanged();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: y.toString(),
                keyboardType: TextInputType.number,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  labelText: 'Y Position on Map (meters)',
                  labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  filled: true,
                  fillColor: AppColors.surfaceSunken,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                ),
                onChanged: (v) {
                  widget.node.params['y'] = double.tryParse(v) ?? 0.0;
                  widget.onChanged();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: theta.toString(),
          keyboardType: TextInputType.number,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Facing Direction (Radians, 0 = forward)',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          onChanged: (v) {
            widget.node.params['theta'] = double.tryParse(v) ?? 0.0;
            widget.onChanged();
          },
        ),
      ],
    );
  }

  Widget _buildStartInspector() {
    final trigger = widget.node.params['trigger'] as String? ?? 'manual';
    final enabled = widget.node.params['enabled'] as bool? ?? true;
    final intervalMinutes = (widget.node.params['interval_minutes'] as num?)?.toInt() ?? 30;
    final scheduleType = widget.node.params['schedule_type'] as String? ?? 'daily';
    final scheduleHour = (widget.node.params['schedule_hour'] as num?)?.toInt() ?? 9;
    final scheduleMinute = (widget.node.params['schedule_minute'] as num?)?.toInt() ?? 0;
    final weekdays = ((widget.node.params['weekdays'] as List?)?.cast<int>() ?? [0, 1, 2, 3, 4]).toSet();
    final scheduleDate = widget.node.params['schedule_date'] as String? ??
        DateTime.now().toIso8601String().substring(0, 10);
    final minBattery = (widget.node.params['min_battery'] as num?)?.toDouble() ?? 20.0;
    final skipIfBusy = widget.node.params['skip_if_busy'] as bool? ?? true;
    final requireActiveMap = widget.node.params['require_active_map'] as bool? ?? true;

    const weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    String timeFormatted() {
      final hour12 = scheduleHour == 0 ? 12 : (scheduleHour > 12 ? scheduleHour - 12 : scheduleHour);
      final amPm = scheduleHour >= 12 ? 'PM' : 'AM';
      final minStr = scheduleMinute.toString().padLeft(2, '0');
      return '$hour12:$minStr $amPm (${scheduleHour.toString().padLeft(2, '0')}:$minStr)';
    }

    String summaryText() {
      if (trigger == 'interval') {
        final hours = intervalMinutes ~/ 60;
        final mins = intervalMinutes % 60;
        final durationStr = hours > 0 ? (mins > 0 ? '${hours}h ${mins}m' : '${hours}h') : '${mins}m';
        return enabled
            ? '⏰ Auto-Trigger: Repeats every $durationStr ($intervalMinutes min)'
            : '⏸ Trigger Paused: Every $durationStr ($intervalMinutes min)';
      } else if (trigger == 'schedule') {
        String repStr = 'Daily';
        if (scheduleType == 'weekly') {
          final days = weekdays.map((d) => d >= 0 && d < 7 ? weekdayLabels[d] : '').where((s) => s.isNotEmpty).join(', ');
          repStr = days.isEmpty ? 'Weekly (No days selected)' : 'Weekly ($days)';
        } else if (scheduleType == 'once') {
          repStr = 'Once on $scheduleDate';
        }
        return enabled
            ? '⏰ Auto-Trigger: $repStr at ${timeFormatted()}'
            : '⏸ Trigger Paused: $repStr at ${timeFormatted()}';
      }
      return '▶ On-Demand / Manual: Triggers when started via app, API, or touchscreen.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary & State Banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: trigger == 'manual'
                ? AppColors.surfaceSunken
                : (enabled ? AppColors.primary.withValues(alpha: 0.08) : AppColors.warning.withValues(alpha: 0.1)),
            borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
            border: Border.all(
              color: trigger == 'manual'
                  ? AppColors.border
                  : (enabled ? AppColors.primary.withValues(alpha: 0.4) : AppColors.warning),
            ),
          ),
          child: Row(
            children: [
              Icon(
                trigger == 'manual'
                    ? Icons.play_circle_fill_rounded
                    : (trigger == 'interval' ? Icons.timer_rounded : Icons.alarm_rounded),
                size: 22,
                color: trigger == 'manual'
                    ? AppColors.textSecondary
                    : (enabled ? AppColors.primary : AppColors.warning),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  summaryText(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: trigger == 'manual'
                        ? AppColors.textPrimary
                        : (enabled ? AppColors.primary : AppColors.textPrimary),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Trigger Mode Selector
        const Text(
          'Workflow Trigger Mode',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Choose how this mission should be started:',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 8),

        Row(
          children: [
            Expanded(
              child: _buildTriggerModeCard(
                title: 'Manual / API',
                subtitle: 'On-demand run',
                icon: Icons.touch_app_rounded,
                selected: trigger == 'manual',
                onTap: widget.readOnly
                    ? null
                    : () {
                        widget.node.params['trigger'] = 'manual';
                        widget.onChanged();
                      },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildTriggerModeCard(
                title: 'Interval Timer',
                subtitle: 'Every X min',
                icon: Icons.timelapse_rounded,
                selected: trigger == 'interval',
                onTap: widget.readOnly
                    ? null
                    : () {
                        widget.node.params['trigger'] = 'interval';
                        widget.node.params.putIfAbsent('interval_minutes', () => 30);
                        widget.onChanged();
                      },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildTriggerModeCard(
                title: 'Clock Alarm',
                subtitle: 'Time & days',
                icon: Icons.alarm_rounded,
                selected: trigger == 'schedule',
                onTap: widget.readOnly
                    ? null
                    : () {
                        widget.node.params['trigger'] = 'schedule';
                        widget.node.params.putIfAbsent('schedule_type', () => 'daily');
                        widget.node.params.putIfAbsent('schedule_hour', () => 9);
                        widget.node.params.putIfAbsent('schedule_minute', () => 0);
                        widget.onChanged();
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // If trigger is Interval
        if (trigger == 'interval') ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    const Text(
                      'Recurring Interval Settings',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Every $intervalMinutes min',
                        style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Quick Presets:', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final preset in [5, 10, 15, 30, 45, 60, 120, 240])
                      ActionChip(
                        label: Text(preset < 60 ? '$preset min' : '${preset ~/ 60} hr${preset > 60 ? 's' : ''}'),
                        labelStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: intervalMinutes == preset ? FontWeight.bold : FontWeight.normal,
                          color: intervalMinutes == preset ? AppColors.textOnPrimary : AppColors.textPrimary,
                        ),
                        backgroundColor: intervalMinutes == preset ? AppColors.primary : AppColors.surfaceSunken,
                        side: BorderSide(
                          color: intervalMinutes == preset ? AppColors.primary : AppColors.border,
                        ),
                        onPressed: widget.readOnly
                            ? null
                            : () {
                                widget.node.params['interval_minutes'] = preset;
                                widget.onChanged();
                              },
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildNumberSlider(
                  label: 'Custom Interval (Minutes)',
                  value: intervalMinutes.toDouble().clamp(1.0, 360.0),
                  min: 1.0,
                  max: 360.0,
                  divisions: 359,
                  onChanged: (v) {
                    if (widget.readOnly) return;
                    widget.node.params['interval_minutes'] = v.round();
                    widget.onChanged();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // If trigger is Clock Alarm / Schedule
        if (trigger == 'schedule') ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.alarm_on_rounded, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    const Text(
                      'Alarm Time & Days',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Time Picker Button
                InkWell(
                  onTap: widget.readOnly
                      ? null
                      : () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay(hour: scheduleHour, minute: scheduleMinute),
                          );
                          if (picked != null) {
                            widget.node.params['schedule_hour'] = picked.hour;
                            widget.node.params['schedule_minute'] = picked.minute;
                            widget.onChanged();
                          }
                        },
                  borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSunken,
                      borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time_rounded, color: AppColors.primary, size: 24),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Trigger Time', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                            Text(
                              timeFormatted(),
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const Spacer(),
                        const Icon(Icons.edit_calendar_rounded, color: AppColors.primary, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Repeat Mode Selector
                const Text('Repeat Schedule:', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (final mode in [
                      ('daily', 'Every Day', Icons.calendar_today_rounded),
                      ('weekly', 'Select Days', Icons.view_week_rounded),
                      ('once', 'One-Time', Icons.event_rounded),
                    ]) ...[
                      ChoiceChip(
                        label: Text(mode.$2),
                        avatar: Icon(mode.$3, size: 14),
                        selected: scheduleType == mode.$1,
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: scheduleType == mode.$1 ? FontWeight.bold : FontWeight.normal,
                          color: scheduleType == mode.$1 ? AppColors.textOnPrimary : AppColors.textPrimary,
                        ),
                        onSelected: widget.readOnly
                            ? null
                            : (sel) {
                                if (sel) {
                                  widget.node.params['schedule_type'] = mode.$1;
                                  widget.onChanged();
                                }
                              },
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),

                // If Weekly: Day Chips
                if (scheduleType == 'weekly') ...[
                  const SizedBox(height: 12),
                  const Text('Days of Week:', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (int i = 0; i < 7; i++)
                        FilterChip(
                          label: Text(weekdayLabels[i]),
                          selected: weekdays.contains(i),
                          selectedColor: AppColors.primary,
                          labelStyle: TextStyle(
                            fontSize: 11,
                            fontWeight: weekdays.contains(i) ? FontWeight.bold : FontWeight.normal,
                            color: weekdays.contains(i) ? AppColors.textOnPrimary : AppColors.textPrimary,
                          ),
                          onSelected: widget.readOnly
                              ? null
                              : (sel) {
                                  if (sel) {
                                    weekdays.add(i);
                                  } else {
                                    weekdays.remove(i);
                                  }
                                  widget.node.params['weekdays'] = weekdays.toList()..sort();
                                  widget.onChanged();
                                },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                        icon: const Icon(Icons.work_outline_rounded, size: 14),
                        label: const Text('Mon–Fri (Weekdays)', style: TextStyle(fontSize: 11)),
                        onPressed: widget.readOnly
                            ? null
                            : () {
                                widget.node.params['weekdays'] = [0, 1, 2, 3, 4];
                                widget.onChanged();
                              },
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                        icon: const Icon(Icons.weekend_outlined, size: 14),
                        label: const Text('Sat–Sun (Weekends)', style: TextStyle(fontSize: 11)),
                        onPressed: widget.readOnly
                            ? null
                            : () {
                                widget.node.params['weekdays'] = [5, 6];
                                widget.onChanged();
                              },
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                        icon: const Icon(Icons.all_inclusive_rounded, size: 14),
                        label: const Text('All 7 Days', style: TextStyle(fontSize: 11)),
                        onPressed: widget.readOnly
                            ? null
                            : () {
                                widget.node.params['weekdays'] = [0, 1, 2, 3, 4, 5, 6];
                                widget.onChanged();
                              },
                      ),
                    ],
                  ),
                ],

                // If Once: Date Picker
                if (scheduleType == 'once') ...[
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: widget.readOnly
                        ? null
                        : () async {
                            final now = DateTime.now();
                            final parsed = DateTime.tryParse(scheduleDate) ?? now;
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: parsed.isBefore(now) ? now : parsed,
                              firstDate: now,
                              lastDate: now.add(const Duration(days: 365 * 2)),
                            );
                            if (picked != null) {
                              widget.node.params['schedule_date'] =
                                  '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                              widget.onChanged();
                            }
                          },
                    borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSunken,
                        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.event_rounded, color: AppColors.primary, size: 18),
                          const SizedBox(width: 8),
                          Text('Date: $scheduleDate', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          const Text('Change Date', style: TextStyle(fontSize: 11, color: AppColors.primary)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // If trigger is automated (interval or schedule), show Active Toggle & Safety
        if (trigger != 'manual') ...[
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Schedule Enabled & Active', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    enabled ? 'Robot will automatically fire this workflow when due' : 'Trigger paused — will not fire automatically',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                  value: enabled,
                  activeThumbColor: AppColors.primary,
                  onChanged: widget.readOnly
                      ? null
                      : (val) {
                          widget.node.params['enabled'] = val;
                          widget.onChanged();
                        },
                ),
                const Divider(height: 1, color: AppColors.border),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.shield_outlined, size: 16, color: AppColors.primary),
                          const SizedBox(width: 6),
                          const Text('Auto-Trigger Safety Guards', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildNumberSlider(
                        label: 'Min Battery to Auto-Trigger (%)',
                        value: minBattery.clamp(10.0, 50.0),
                        min: 10.0,
                        max: 50.0,
                        divisions: 8,
                        onChanged: (v) {
                          if (widget.readOnly) return;
                          widget.node.params['min_battery'] = v;
                          widget.onChanged();
                        },
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Skip trigger if robot is already busy', style: TextStyle(fontSize: 11.5)),
                        value: skipIfBusy,
                        activeColor: AppColors.primary,
                        onChanged: widget.readOnly
                            ? null
                            : (v) {
                                widget.node.params['skip_if_busy'] = v ?? true;
                                widget.onChanged();
                              },
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Require active map to match mission map', style: TextStyle(fontSize: 11.5)),
                        value: requireActiveMap,
                        activeColor: AppColors.primary,
                        onChanged: widget.readOnly
                            ? null
                            : (v) {
                                widget.node.params['require_active_map'] = v ?? true;
                                widget.onChanged();
                              },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _buildTriggerModeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.08) : AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.8 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: selected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                color: selected ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9.5,
                color: selected ? AppColors.primary.withValues(alpha: 0.8) : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitInspector() {
    final dur = (widget.node.params['duration_sec'] as num?)?.toDouble() ?? 5.0;

    return _buildNumberSlider(
      label: 'How many seconds to pause and wait',
      value: dur,
      min: 1.0,
      max: 60.0,
      divisions: 59,
      onChanged: (v) {
        widget.node.params['duration_sec'] = v;
        widget.onChanged();
      },
    );
  }

  Widget _buildConditionInspector() {
    final expr = widget.node.params['expression'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildVariableInputField(
          label: 'Rule to check',
          initialValue: expr,
          hintText: 'e.g. form.status == "Pass" or {battery_pct} < 20',
          helperText: 'If this rule is true, robot follows Yes path; otherwise No path (supports {variables})',
          onChanged: (v) {
            widget.node.params['expression'] = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 10),
        const Text(
          'Quick Rule Examples (tap to use):',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _buildTokenChip('form.status == "Pass"'),
            _buildTokenChip('{battery_pct} < 20'),
            _buildTokenChip('{choice_result} == "Yes"'),
          ],
        ),
      ],
    );
  }

  Widget _buildTokenChip(String token) {
    return ActionChip(
      backgroundColor: AppColors.surfaceSunken,
      side: const BorderSide(color: AppColors.border),
      label: Text(token, style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w500)),
      onPressed: widget.readOnly
          ? null
          : () {
              setState(() {
                widget.node.params['expression'] = token;
              });
              widget.onChanged();
            },
    );
  }

  Widget _buildUiInteractionInspector() {
    final subtype = widget.node.params['subtype'] as String? ?? 'dynamic_form';
    final title = widget.node.params['title'] as String? ?? 'Operator Input';
    final timeout = (widget.node.params['timeout_sec'] as num?)?.toDouble() ?? 60.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Subtype Dropdown
        DropdownButtonFormField<String>(
          key: ValueKey('${widget.node.id}_subtype_$subtype'),
          isExpanded: true,
          initialValue: ['dynamic_form', 'kiosk'].contains(subtype) ? subtype : 'dynamic_form',
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'What kind of screen to show?',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          items: [
            const DropdownMenuItem(value: 'dynamic_form', child: Text('Form / Checklist (Questions to answer)', overflow: TextOverflow.ellipsis)),
            const DropdownMenuItem(value: 'kiosk', child: Text('Destination Picker (User picks room)', overflow: TextOverflow.ellipsis)),
            if (!['dynamic_form', 'kiosk'].contains(subtype))
              DropdownMenuItem(value: subtype, child: Text('Legacy: $subtype', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: widget.readOnly
              ? null
              : (val) {
                  setState(() {
                    widget.node.params['subtype'] = val;
                  });
                  widget.onChanged();
                },
        ),
        const SizedBox(height: 12),

        // Target Display Surface Dropdown
        DropdownButtonFormField<String>(
          key: ValueKey('${widget.node.id}_target_${widget.node.params['target']}'),
          isExpanded: true,
          initialValue: ['robot_screen', 'operator_app', 'both'].contains(widget.node.params['target'])
              ? widget.node.params['target']
              : 'robot_screen',
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Where should this screen appear?',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          items: const [
            DropdownMenuItem(value: 'robot_screen', child: Text('Robot Screen (Touchscreen on robot)', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'operator_app', child: Text('Your Screen (This app / controller)', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'both', child: Text('Both Robot and Your App', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: widget.readOnly
              ? null
              : (val) {
                  setState(() {
                    widget.node.params['target'] = val;
                  });
                  widget.onChanged();
                },
        ),
        const SizedBox(height: 12),

        _buildVariableInputField(
          label: 'Screen Title (Header shown to user)',
          initialValue: title,
          onChanged: (v) {
            widget.node.params['title'] = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),

        _buildNumberSlider(
          label: 'Time limit to respond (seconds)',
          value: timeout,
          min: 10.0,
          max: 300.0,
          divisions: 29,
          onChanged: (v) {
            widget.node.params['timeout_sec'] = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _buildVariableInputField(
          label: 'Save Entire Form to Variable (Optional)',
          initialValue: widget.node.params['output_variable'] as String? ?? widget.node.params['variable_name'] as String? ?? '',
          hintText: 'e.g. user_form_data',
          prefixIcon: const Icon(Icons.data_object, size: 16),
          onChanged: (v) {
            final val = v.trim();
            widget.node.params['output_variable'] = val;
            widget.node.params['variable_name'] = val;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '💡 Every question key (e.g. {field_1} or custom key like {room}) is automatically saved as a variable! You can use {key} in later steps (such as HTTP requests, ROS topics, Screen titles, or TTS voice messages).',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.35),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Subtype specific builders
        if (subtype == 'dynamic_form') _buildDynamicFormFieldsEditor(),
        if (subtype == 'choice') _buildChoiceOptionsEditor(),
        if (subtype == 'media_display') _buildMediaUrlEditor(),
      ],
    );
  }

  Widget _buildUiNotificationInspector() {
    final title = widget.node.params['title'] as String? ?? 'Notice';
    final message = widget.node.params['message'] as String? ?? '';
    final buttonText = widget.node.params['button_text'] as String? ?? 'OK';
    final timeout = (widget.node.params['timeout_sec'] as num?)?.toDouble() ?? 30.0;
    final soundAlert = widget.node.params['sound_alert'] != false;
    final speechText = widget.node.params['speech_text'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('${widget.node.id}_target_${widget.node.params['target']}'),
          isExpanded: true,
          initialValue: ['robot_screen', 'operator_app', 'both'].contains(widget.node.params['target'])
              ? widget.node.params['target']
              : 'robot_screen',
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Where should notification appear?',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius)),
          ),
          items: const [
            DropdownMenuItem(value: 'robot_screen', child: Text('Robot Screen (Touchscreen)')),
            DropdownMenuItem(value: 'operator_app', child: Text('Operator App (This screen)')),
            DropdownMenuItem(value: 'both', child: Text('Both Robot and App')),
          ],
          onChanged: widget.readOnly
              ? null
              : (val) {
                  setState(() => widget.node.params['target'] = val);
                  widget.onChanged();
                },
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: title,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Notification Title',
            hintText: 'e.g. Delivery Arrived',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius)),
          ),
          onChanged: widget.readOnly
              ? null
              : (val) {
                  widget.node.params['title'] = val;
                  widget.onChanged();
                },
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: message,
          maxLines: 3,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Description / Message',
            hintText: 'e.g. The robot has arrived. Tap OK to acknowledge.',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius)),
          ),
          onChanged: widget.readOnly
              ? null
              : (val) {
                  widget.node.params['message'] = val;
                  widget.onChanged();
                },
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: buttonText,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Confirmation Button Label',
            hintText: 'e.g. OK or Got It',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius)),
          ),
          onChanged: widget.readOnly
              ? null
              : (val) {
                  widget.node.params['button_text'] = val.trim().isNotEmpty ? val.trim() : 'OK';
                  widget.onChanged();
                },
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: timeout.toString(),
          keyboardType: TextInputType.number,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Auto-Dismiss Timeout (Seconds)',
            hintText: '30 (0 for indefinite until tapped)',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius)),
          ),
          onChanged: widget.readOnly
              ? null
              : (val) {
                  widget.node.params['timeout_sec'] = double.tryParse(val) ?? 30.0;
                  widget.onChanged();
                },
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: speechText,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Spoken Voice Announcement (Optional TTS)',
            hintText: 'e.g. Robot has arrived. Please tap OK.',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius)),
          ),
          onChanged: widget.readOnly
              ? null
              : (val) {
                  widget.node.params['speech_text'] = val;
                  widget.onChanged();
                },
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Play Alert Chime', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          subtitle: const Text('Sound chime tone when notification appears', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          value: soundAlert,
          activeThumbColor: AppColors.primary,
          activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
          contentPadding: EdgeInsets.zero,
          onChanged: widget.readOnly
              ? null
              : (val) {
                  setState(() => widget.node.params['sound_alert'] = val);
                  widget.onChanged();
                },
        ),
      ],
    );
  }

  Widget _buildUiChoiceInspector() {
    final title = widget.node.params['title'] as String? ?? 'Choose an Option';
    final message = widget.node.params['message'] as String? ?? 'Please tap one of the options below:';
    final outVar = widget.node.params['output_variable'] as String? ?? widget.node.params['variable_name'] as String? ?? '';
    final timeout = (widget.node.params['timeout_sec'] as num?)?.toDouble() ?? 60.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('${widget.node.id}_target_${widget.node.params['target']}'),
          isExpanded: true,
          initialValue: ['robot_screen', 'operator_app', 'both'].contains(widget.node.params['target'])
              ? widget.node.params['target']
              : 'robot_screen',
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Where should choices appear?',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius)),
          ),
          items: const [
            DropdownMenuItem(value: 'robot_screen', child: Text('Robot Screen (Touchscreen)')),
            DropdownMenuItem(value: 'operator_app', child: Text('Operator App (This screen)')),
            DropdownMenuItem(value: 'both', child: Text('Both Robot and App')),
          ],
          onChanged: widget.readOnly
              ? null
              : (val) {
                  setState(() => widget.node.params['target'] = val);
                  widget.onChanged();
                },
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: title,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Dialog Title',
            hintText: 'e.g. Confirm Delivery',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius)),
          ),
          onChanged: (v) {
            widget.node.params['title'] = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: message,
          maxLines: 2,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Prompt Message (supports {variable})',
            hintText: 'e.g. Deliver items to room {room}?',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius)),
          ),
          onChanged: (v) {
            widget.node.params['message'] = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: outVar,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Save Choice to Variable (Optional)',
            hintText: 'e.g. user_decision',
            prefixIcon: const Icon(Icons.data_object, size: 16),
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius)),
          ),
          onChanged: (v) {
            final val = v.trim();
            widget.node.params['output_variable'] = val;
            widget.node.params['variable_name'] = val;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _buildNumberSlider(
          label: 'Timeout limit (seconds)',
          value: timeout,
          min: 5.0,
          max: 300.0,
          divisions: 59,
          onChanged: (v) {
            widget.node.params['timeout_sec'] = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 14),
        _buildChoiceOptionsEditor(),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lightbulb_outline, size: 16, color: AppColors.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '💡 The selected choice is automatically saved to {selected_choice} (and your custom variable above). You can connect outgoing branch wires for each button name (e.g. "yes", "no").',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSetVariableInspector() {
    final key = widget.node.params['key'] as String? ?? widget.node.params['name'] as String? ?? '';
    final val = widget.node.params['value']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildVariableInputField(
          label: 'Variable Name',
          initialValue: key,
          hintText: 'e.g. target_room or guest_count',
          prefixIcon: const Icon(Icons.label_outline, size: 16),
          onChanged: (v) {
            final trimmed = v.trim();
            widget.node.params['key'] = trimmed;
            widget.node.params['name'] = trimmed;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _buildVariableInputField(
          label: 'Variable Value (supports text, numbers, or {variables})',
          initialValue: val,
          maxLines: 2,
          hintText: 'e.g. 302, "VIP", or {user_entered_room}',
          prefixIcon: const Icon(Icons.edit_note, size: 16),
          onChanged: (v) {
            if (num.tryParse(v) != null && !v.contains('{')) {
              widget.node.params['value'] = num.parse(v);
            } else {
              widget.node.params['value'] = v;
            }
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '💡 Stored variables can be used in later nodes (such as Screen text, Voice speech, HTTP URLs, or Waypoints) using {variable_name}.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDynamicFormFieldsEditor() {
    final rawFields = (widget.node.params['fields'] as List? ?? []);
    final fields = [
      for (final f in rawFields)
        if (f is Map<String, dynamic>) FormFieldDef.fromJson(f)
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Questions & Input Fields',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            if (!widget.readOnly)
              TextButton.icon(
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('+ Add Question', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                onPressed: () {
                  setState(() {
                    final newField = FormFieldDef(
                      key: 'field_${fields.length + 1}',
                      label: 'Question ${fields.length + 1}',
                      type: 'text',
                    );
                    fields.add(newField);
                    widget.node.params['fields'] = fields.map((f) => f.toJson()).toList();
                  });
                  widget.onChanged();
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < fields.length; i++)
          Card(
            color: AppColors.surfaceElevated,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.border),
            ),
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: fields[i].label,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: 'Question or Field Title',
                            hintText: 'e.g. What is the room temperature?',
                            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                            filled: true,
                            fillColor: AppColors.surfaceSunken,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                          ),
                          onChanged: (v) {
                            fields[i].label = v;
                            widget.node.params['fields'] = fields.map((f) => f.toJson()).toList();
                            widget.onChanged();
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.textTertiary),
                        tooltip: 'Remove Question',
                        onPressed: widget.readOnly
                            ? null
                            : () {
                                setState(() {
                                  fields.removeAt(i);
                                  widget.node.params['fields'] = fields.map((f) => f.toJson()).toList();
                                });
                                widget.onChanged();
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('${widget.node.id}_field_${i}_${fields[i].type}'),
                          isExpanded: true,
                          initialValue: ['text', 'number', 'select', 'location', 'checkbox', 'switch', 'signature'].contains(fields[i].type) ? fields[i].type : 'text',
                          dropdownColor: AppColors.surface,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w500),
                          isDense: true,
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: 'Answer Type',
                            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                            filled: true,
                            fillColor: AppColors.surfaceSunken,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'text', child: Text('Short Text (Type an answer)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'number', child: Text('Number (Enter digits)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'select', child: Text('Dropdown List (Choose custom choices)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'location', child: Text('📍 Saved Locations (Pick place from map)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'checkbox', child: Text('Checkmark Box', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'switch', child: Text('On / Off Toggle', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'signature', child: Text('Sign on Screen', overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: widget.readOnly
                              ? null
                              : (v) {
                                  setState(() {
                                    fields[i].type = v ?? 'text';
                                    widget.node.params['fields'] = fields.map((f) => f.toJson()).toList();
                                  });
                                  widget.onChanged();
                                },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Checkbox(
                        value: fields[i].required,
                        activeColor: AppColors.primary,
                        onChanged: widget.readOnly
                            ? null
                            : (v) {
                                setState(() {
                                  fields[i].required = v ?? false;
                                  widget.node.params['fields'] = fields.map((f) => f.toJson()).toList();
                                });
                                widget.onChanged();
                              },
                      ),
                      const Text('Required', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    ],
                  ),
                  if (fields[i].type == 'select') ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('List of Choices (Tap ✕ to remove):', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: fields[i].options.map((opt) {
                              return Chip(
                                label: Text(opt, style: const TextStyle(fontSize: 11)),
                                padding: EdgeInsets.zero,
                                backgroundColor: AppColors.surfaceSunken,
                                deleteIcon: const Icon(Icons.close, size: 14),
                                onDeleted: widget.readOnly ? null : () {
                                  setState(() {
                                    fields[i].options.remove(opt);
                                    if (fields[i].defaultValue == opt) fields[i].defaultValue = null;
                                    widget.node.params['fields'] = fields.map((f) => f.toJson()).toList();
                                  });
                                  widget.onChanged();
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: 'Type choice & press Enter...',
                                    hintStyle: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                  style: const TextStyle(fontSize: 11),
                                  onSubmitted: widget.readOnly ? null : (val) {
                                    if (val.trim().isNotEmpty && !fields[i].options.contains(val.trim())) {
                                      setState(() {
                                        fields[i].options.add(val.trim());
                                        widget.node.params['fields'] = fields.map((f) => f.toJson()).toList();
                                      });
                                      widget.onChanged();
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            key: ValueKey('${widget.node.id}_field_${i}_def_${fields[i].defaultValue}'),
                            isExpanded: true,
                            initialValue: fields[i].options.contains(fields[i].defaultValue) ? fields[i].defaultValue : null,
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: 'Pre-selected Default Choice (Optional)',
                              labelStyle: const TextStyle(fontSize: 11),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                            style: const TextStyle(fontSize: 11, color: AppColors.textPrimary),
                            items: [
                              const DropdownMenuItem<String>(value: null, child: Text('None (User must choose)')),
                              for (final opt in fields[i].options)
                                DropdownMenuItem(value: opt, child: Text(opt)),
                            ],
                            onChanged: widget.readOnly ? null : (val) {
                              setState(() {
                                fields[i].defaultValue = val;
                                widget.node.params['fields'] = fields.map((f) => f.toJson()).toList();
                              });
                              widget.onChanged();
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildChoiceOptionsEditor() {
    final options = (widget.node.params['options'] as List? ?? ['Yes', 'No']).map((e) => e.toString()).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Touch Buttons to Display', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
            if (!widget.readOnly)
              TextButton.icon(
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('+ Add Button', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                onPressed: () {
                  setState(() {
                    options.add('Button ${options.length + 1}');
                    widget.node.params['options'] = options;
                  });
                  widget.onChanged();
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (int i = 0; i < options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: options[i],
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Button Text (e.g. Yes, No, Done)',
                      filled: true,
                      fillColor: AppColors.surfaceSunken,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                    ),
                    onChanged: (v) {
                      options[i] = v;
                      widget.node.params['options'] = options;
                      widget.onChanged();
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.textTertiary),
                  tooltip: 'Delete Button',
                  onPressed: widget.readOnly
                      ? null
                      : () {
                          setState(() {
                            options.removeAt(i);
                            widget.node.params['options'] = options;
                          });
                          widget.onChanged();
                        },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMediaUrlEditor() {
    final mediaUrl = widget.node.params['media_url'] as String? ?? '';

    return _buildVariableInputField(
      label: 'Link to Picture or Video (URL)',
      initialValue: mediaUrl,
      hintText: 'https://example.com/picture.png',
      helperText: 'Direct web link to an image or MP4 video (supports {variables})',
      onChanged: (v) {
        widget.node.params['media_url'] = v;
        widget.onChanged();
      },
    );
  }

  Widget _buildCallApiInspector() {
    final method = widget.node.params['method'] as String? ?? 'POST';
    final url = widget.node.params['url'] as String? ?? '';
    final token = widget.node.params['bearer_token'] as String? ?? '';
    final headers = widget.node.params['headers'] as String? ?? '{}';
    final payload = widget.node.params['payload'] as String? ?? '{}';

    return Column(
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('${widget.node.id}_method_$method'),
          isExpanded: true,
          initialValue: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'].contains(method) ? method : 'POST',
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Web Request Type',
            labelStyle: const TextStyle(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          items: const [
            DropdownMenuItem(value: 'GET', child: Text('GET (Retrieve Data)')),
            DropdownMenuItem(value: 'POST', child: Text('POST (Send Data / Trigger Event)')),
            DropdownMenuItem(value: 'PUT', child: Text('PUT (Replace Data)')),
            DropdownMenuItem(value: 'DELETE', child: Text('DELETE (Remove Data)')),
            DropdownMenuItem(value: 'PATCH', child: Text('PATCH (Update Partial Data)')),
          ],
          onChanged: widget.readOnly
              ? null
              : (v) {
                  widget.node.params['method'] = v;
                  widget.onChanged();
                },
        ),
        const SizedBox(height: 12),
        _buildVariableInputField(
          label: 'Web Address (URL)',
          initialValue: url,
          hintText: 'https://api.example.com/webhook',
          onChanged: (v) {
            widget.node.params['url'] = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _buildVariableInputField(
          label: 'Secret Key / Access Token (Optional)',
          initialValue: token,
          hintText: 'Bearer token or auth key',
          prefixIcon: const Icon(Icons.key, size: 16),
          onChanged: (v) {
            widget.node.params['bearer_token'] = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _buildVariableInputField(
          label: 'Custom Headers (JSON, optional)',
          initialValue: headers,
          maxLines: 2,
          hintText: '{"Content-Type": "application/json"}',
          onChanged: (v) {
            widget.node.params['headers'] = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _buildVariableInputField(
          label: 'Message Data to Send (JSON, optional)',
          initialValue: payload,
          maxLines: 3,
          hintText: '{"status": "completed"}',
          onChanged: (v) {
            widget.node.params['payload'] = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _buildNumberSlider(
          label: 'Wait for response up to (seconds)',
          value: (widget.node.params['timeout_sec'] as num?)?.toDouble() ?? 10.0,
          min: 1.0,
          max: 120.0,
          divisions: 119,
          onChanged: (v) {
            widget.node.params['timeout_sec'] = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _buildVariableInputField(
          label: 'Save API Response to Variable (Optional)',
          initialValue: widget.node.params['output_variable'] as String? ?? widget.node.params['variable_name'] as String? ?? '',
          hintText: 'e.g. api_response or weather_info',
          prefixIcon: const Icon(Icons.data_object, size: 16),
          onChanged: (v) {
            final val = v.trim();
            widget.node.params['output_variable'] = val;
            widget.node.params['variable_name'] = val;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lightbulb_outline, size: 16, color: AppColors.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '💡 You can insert any previous variable into the URL, Headers, or Payload using {variable_name}. Any JSON response will be saved into the variable above!',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNotifyInspector() {
    final oled = widget.node.params['oled_text'] as String? ?? '';
    final led = widget.node.params['led_cmd'] as String? ?? '';

    return Column(
      children: [
        _buildVariableInputField(
          label: 'Robot Face Screen Text',
          initialValue: oled,
          hintText: 'e.g. HELLO! or MISSION DONE',
          helperText: 'Short text banner displayed on front display (supports {variables})',
          onChanged: (v) {
            widget.node.params['oled_text'] = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _buildVariableInputField(
          label: 'Light Colors / Pattern',
          initialValue: led,
          hintText: 'solid,0,200,40',
          helperText: 'Changes light ring (format: solid,Red,Green,Blue)',
          onChanged: (v) {
            widget.node.params['led_cmd'] = v;
            widget.onChanged();
          },
        ),
      ],
    );
  }

  Widget _buildLiveFormPreview() {
    final title = widget.node.params['title'] as String? ?? 'Form Preview';
    final rawFields = (widget.node.params['fields'] as List? ?? []);
    final fields = [
      for (final f in rawFields)
        if (f is Map<String, dynamic>) FormFieldDef.fromJson(f)
    ];

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(16),
      child: Card(
        color: AppColors.surface,
        elevation: 2,
        shadowColor: AppColors.shadowTint.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const Divider(color: AppColors.border),
              if (fields.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No fields configured yet.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: fields.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final f = fields[i];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${f.label}${f.required ? ' *' : ''}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          if (f.type == 'switch')
                            Switch(value: false, activeThumbColor: AppColors.primary, onChanged: (_) {})
                          else if (f.type == 'checkbox')
                            Checkbox(value: false, activeColor: AppColors.primary, onChanged: (_) {})
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceSunken,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Text(
                                f.type == 'select' ? 'Select from options...' : 'Enter ${f.label.toLowerCase()}...',
                                style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {},
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.textOnPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.buttonRadius)),
                ),
                child: const Text('Submit Form'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEndMissionInspector() {
    final status = widget.node.params['status'] as String? ?? 'success';
    final message = widget.node.params['message'] as String? ?? 'Mission completed successfully.';
    final dockOnEnd = widget.node.params['dock_on_end'] as bool? ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('${widget.node.id}_status_$status'),
          isExpanded: true,
          initialValue: ['success', 'failed', 'aborted'].contains(status) ? status : 'success',
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Final Mission Outcome',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          items: const [
            DropdownMenuItem(value: 'success', child: Text('Success (Mission finished well)', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'failed', child: Text('Failed (Stopped because of a problem)', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'aborted', child: Text('Cancelled (Stopped by operator)', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: widget.readOnly
              ? null
              : (val) {
                  setState(() => widget.node.params['status'] = val);
                  widget.onChanged();
                },
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: message,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Farewell / Summary Note',
            hintText: 'e.g. Mission completed successfully.',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          onChanged: (v) {
            widget.node.params['message'] = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Drive to Charger Automatically', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          subtitle: const Text('Robot will safely return to charging dock when this step finishes', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          value: dockOnEnd,
          activeThumbColor: AppColors.primary,
          onChanged: widget.readOnly
              ? null
              : (v) {
                  setState(() => widget.node.params['dock_on_end'] = v);
                  widget.onChanged();
                },
        ),
      ],
    );
  }

  Widget _buildLoopInspector() {
    final count = (widget.node.params['count'] as num?)?.toInt() ?? 3;
    final varName = widget.node.params['variable_name'] as String? ?? 'loop_index';
    final condition = widget.node.params['condition'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNumberSlider(
          label: 'How many times to repeat?',
          value: count.toDouble(),
          min: 1.0,
          max: 50.0,
          divisions: 49,
          onChanged: (v) {
            setState(() => widget.node.params['count'] = v.toInt());
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: varName,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Repetition Counter Name (Optional)',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            helperText: 'Stores current repetition count (0, 1, 2...) for rules or messages',
            helperStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          onChanged: (v) {
            widget.node.params['variable_name'] = v.trim();
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: condition,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Stop Early Rule (Optional)',
            hintText: 'e.g. form.keep_going == true',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            helperText: 'If this rule becomes false, repeat stops early',
            helperStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          onChanged: (v) {
            widget.node.params['condition'] = v.trim();
            widget.onChanged();
          },
        ),
      ],
    );
  }

  Widget _buildParallelInspector() {
    final node = widget.node;
    final count = (node.params['branch_count'] as num?)?.toInt() ?? 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF00ACC1).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF00ACC1).withValues(alpha: 0.3)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.call_split_rounded, size: 20, color: Color(0xFF00ACC1)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Executes all connected branch paths at the same time. For example, the robot can speak aloud while displaying an interactive form on screen.',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 12, height: 1.35),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Number of Concurrent Branches',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (int i = 2; i <= 5; i++) ...[
              Expanded(
                child: InkWell(
                  onTap: widget.readOnly
                      ? null
                      : () {
                          setState(() {
                            node.params['branch_count'] = i;
                          });
                          widget.onChanged();
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: count == i ? const Color(0xFF00ACC1) : AppColors.surfaceSunken,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: count == i ? const Color(0xFF00ACC1) : AppColors.border,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$i Branches',
                      style: TextStyle(
                        color: count == i ? Colors.white : AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
              if (i < 5) const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildBatteryGuardInspector() {
    final minPct = (widget.node.params['min_battery_pct'] as num?)?.toDouble() ?? 20.0;
    final requireCharging = widget.node.params['require_charging'] as bool? ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNumberSlider(
          label: 'Minimum Battery Level Needed (%)',
          value: minPct,
          min: 5.0,
          max: 95.0,
          divisions: 18,
          onChanged: (v) {
            setState(() => widget.node.params['min_battery_pct'] = v);
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Must Be Plugged In to Charger', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          subtitle: const Text('Robot must currently be docked and charging to pass this check', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          value: requireCharging,
          activeThumbColor: AppColors.primary,
          onChanged: widget.readOnly
              ? null
              : (v) {
                  setState(() => widget.node.params['require_charging'] = v);
                  widget.onChanged();
                },
        ),
      ],
    );
  }

  Widget _buildPatrolLoopInspector() {
    final rawWps = widget.node.params['waypoints'] as List? ?? [];
    final waypoints = rawWps.map((e) => e.toString()).toList();
    final laps = (widget.node.params['laps'] as num?)?.toInt() ?? 1;
    final dwell = (widget.node.params['dwell_sec'] as num?)?.toDouble() ?? 2.0;
    final availableLocations = LocationsController.instance.value ?? const <Map<String, dynamic>>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Saved Places to Visit in Order', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
            PopupMenuButton<String>(
              icon: const Icon(Icons.add_location_alt_outlined, size: 18, color: AppColors.primary),
              tooltip: 'Add Place to Route',
              onSelected: (wpName) {
                setState(() {
                  waypoints.add(wpName);
                  widget.node.params['waypoints'] = waypoints;
                });
                widget.onChanged();
              },
              itemBuilder: (ctx) => [
                for (final loc in availableLocations)
                  PopupMenuItem(
                    value: loc['name']?.toString() ?? '',
                    child: Text(loc['name']?.toString() ?? ''),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (waypoints.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
              border: Border.all(color: AppColors.border),
            ),
            child: const Text('No stops added yet. Tap the + location icon above to add stops to patrol.', style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
          )
        else
          Column(
            children: [
              for (int i = 0; i < waypoints.length; i++)
                Container(
                  key: ValueKey('${waypoints[i]}_$i'),
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSunken,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Text('${i + 1}.', style: const TextStyle(color: AppColors.textTertiary, fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(waypoints[i], style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600))),
                      if (i > 0)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          tooltip: 'Move Up',
                          icon: const Icon(Icons.arrow_upward, size: 14, color: AppColors.textSecondary),
                          onPressed: () {
                            setState(() {
                              final item = waypoints.removeAt(i);
                              waypoints.insert(i - 1, item);
                              widget.node.params['waypoints'] = waypoints;
                            });
                            widget.onChanged();
                          },
                        ),
                      if (i < waypoints.length - 1)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          tooltip: 'Move Down',
                          icon: const Icon(Icons.arrow_downward, size: 14, color: AppColors.textSecondary),
                          onPressed: () {
                            setState(() {
                              final item = waypoints.removeAt(i);
                              waypoints.insert(i + 1, item);
                              widget.node.params['waypoints'] = waypoints;
                            });
                            widget.onChanged();
                          },
                        ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        tooltip: 'Remove',
                        icon: const Icon(Icons.close, size: 16, color: AppColors.danger),
                        onPressed: () {
                          setState(() {
                            waypoints.removeAt(i);
                            widget.node.params['waypoints'] = waypoints;
                          });
                          widget.onChanged();
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        const SizedBox(height: 12),
        _buildNumberSlider(
          label: 'How many laps around the route? (0 = infinite)',
          value: laps.toDouble(),
          min: 0.0,
          max: 20.0,
          divisions: 20,
          onChanged: (v) {
            setState(() => widget.node.params['laps'] = v.toInt());
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _buildNumberSlider(
          label: 'How many seconds to pause at each stop',
          value: dwell,
          min: 0.0,
          max: 30.0,
          divisions: 30,
          onChanged: (v) {
            setState(() => widget.node.params['dwell_sec'] = v);
            widget.onChanged();
          },
        ),
      ],
    );
  }

  bool _isUploadingMedia = false;

  Future<void> _handleUploadMedia() async {
    final api = widget.api;
    if (api == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Robot connection not available for upload')),
      );
      return;
    }
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'mp4', 'mov', 'avi', 'mkv', 'webm'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.first;
      Uint8List? bytes = picked.bytes;
      if (bytes == null && !kIsWeb && picked.path != null) {
        bytes = await File(picked.path!).readAsBytes();
      }
      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not read media file content')),
          );
        }
        return;
      }

      setState(() => _isUploadingMedia = true);
      final res = await api.uploadMedia(bytes, picked.name);
      final relUrl = res['url']?.toString() ?? '/media/${picked.name}';
      final fullUrl = '${api.baseUrl}$relUrl';

      setState(() {
        _isUploadingMedia = false;
        widget.node.params['url'] = fullUrl;
        final ext = picked.name.split('.').last.toLowerCase();
        if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext)) {
          widget.node.params['media_type'] = 'video';
        } else if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
          widget.node.params['media_type'] = 'image';
        }
      });
      widget.onChanged();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Uploaded ${picked.name} to robot successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingMedia = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Widget _buildUiMediaInspector() {
    final mediaType = widget.node.params['media_type'] as String? ?? 'image';
    final url = widget.node.params['url'] as String? ?? '';
    final duration = (widget.node.params['duration_sec'] as num?)?.toDouble() ?? 15.0;
    final showSkip = widget.node.params['show_skip'] as bool? ?? true;
    final target = widget.node.params['target'] as String? ?? 'robot_screen';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('${widget.node.id}_media_type_$mediaType'),
          isExpanded: true,
          initialValue: ['image', 'video', 'web_url'].contains(mediaType) ? mediaType : 'image',
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'What kind of media to show?',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          items: const [
            DropdownMenuItem(value: 'image', child: Text('Photo / Image (PNG or JPG)', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'video', child: Text('Video Clip (MP4)', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'web_url', child: Text('Web Page / Live Dashboard', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: widget.readOnly
              ? null
              : (val) {
                  setState(() => widget.node.params['media_type'] = val);
                  widget.onChanged();
                },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('${widget.node.id}_media_target_$target'),
          isExpanded: true,
          initialValue: ['robot_screen', 'operator_app', 'both'].contains(target) ? target : 'robot_screen',
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Where should this appear?',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          items: const [
            DropdownMenuItem(value: 'robot_screen', child: Text('Robot Screen (Touchscreen)', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'operator_app', child: Text('Your Computer Screen (This app)', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'both', child: Text('Both Robot and Computer', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: widget.readOnly
              ? null
              : (val) {
                  setState(() => widget.node.params['target'] = val);
                  widget.onChanged();
                },
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                key: ValueKey('${widget.node.id}_url_${widget.node.params['url']}'),
                initialValue: url,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  labelText: 'Web Link or Robot File URL',
                  hintText: 'https://... or http://robot:8080/media/...',
                  labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  filled: true,
                  fillColor: AppColors.surfaceSunken,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                ),
                onChanged: (v) {
                  widget.node.params['url'] = v.trim();
                  widget.onChanged();
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 42,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius)),
                ),
                onPressed: (widget.readOnly || _isUploadingMedia) ? null : _handleUploadMedia,
                icon: _isUploadingMedia
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                    : const Icon(Icons.cloud_upload_outlined, size: 18),
                label: Text(_isUploadingMedia ? '...' : 'Upload'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildNumberSlider(
          label: 'How long to display (seconds)',
          value: duration,
          min: 5.0,
          max: 120.0,
          divisions: 23,
          onChanged: (v) {
            setState(() => widget.node.params['duration_sec'] = v);
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show "Skip" or "Close" Button', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          subtitle: const Text('Allows someone standing by the robot to dismiss the screen early', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          value: showSkip,
          activeThumbColor: AppColors.primary,
          onChanged: widget.readOnly
              ? null
              : (v) {
                  setState(() => widget.node.params['show_skip'] = v);
                  widget.onChanged();
                },
        ),
      ],
    );
  }

  Widget _buildSwitchMissionInspector() {
    final targetId = widget.node.params['target_mission_id'] as String?;
    final transferContext = widget.node.params['transfer_context'] as bool? ?? true;
    final missions = widget.availableMissions;
    final targetExists = missions.any((m) => m['id'] == targetId);
    final effectiveValue = targetExists ? targetId : (targetId != null && targetId.isNotEmpty ? '__deleted__' : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF009688).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(color: const Color(0xFF009688).withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.alt_route_rounded, size: 20, color: Color(0xFF009688)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Transfers autonomous control to another saved mission on this map.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: ValueKey('${widget.node.id}_target_mission_$targetId'),
          isExpanded: true,
          initialValue: effectiveValue,
          dropdownColor: AppColors.surface,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            labelText: 'Target Mission to Switch To',
            labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            filled: true,
            fillColor: AppColors.surfaceSunken,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          ),
          items: [
            for (final m in missions)
              DropdownMenuItem(
                value: m['id'] as String,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        m['name'] as String? ?? m['id'] as String,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (m['map'] != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          m['map'].toString(),
                          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                        ),
                      ),
                  ],
                ),
              ),
            if (!targetExists && targetId != null && targetId.isNotEmpty)
              DropdownMenuItem(
                value: '__deleted__',
                child: Text(
                  '⚠️ Missing / Deleted Mission ($targetId)',
                  style: const TextStyle(color: AppColors.danger, fontStyle: FontStyle.italic),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: widget.readOnly
              ? null
              : (val) {
                  if (val == '__deleted__') return;
                  setState(() => widget.node.params['target_mission_id'] = val);
                  widget.onChanged();
                },
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceSunken,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Pass Variables to Next Mission', style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    SizedBox(height: 2),
                    Text('Forward current form responses, counters, and context', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  ],
                ),
              ),
              Switch(
                value: transferContext,
                activeThumbColor: AppColors.primary,
                onChanged: widget.readOnly
                    ? null
                    : (val) {
                        setState(() => widget.node.params['transfer_context'] = val);
                        widget.onChanged();
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUiSpeechInspector() {
    final text = widget.node.params['text'] as String? ?? '';
    final wait = widget.node.params['wait_completion'] as bool? ?? true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildVariableInputField(
          label: 'What should the robot say out loud?',
          initialValue: text,
          maxLines: 3,
          hintText: 'e.g. Hello {user_name}! I have arrived with your delivery.',
          helperText: 'The robot will use its speaker to speak these exact words (supports {variables})',
          onChanged: (v) {
            widget.node.params['text'] = v;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        if (widget.api != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.volume_up_rounded, size: 16),
              label: const Text('Test Voice on Robot Speaker', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF8B5CF6),
                side: const BorderSide(color: Color(0xFF8B5CF6)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onPressed: text.trim().isEmpty
                  ? null
                  : () async {
                      try {
                        await widget.api!.speak(text.trim());
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Speaking aloud via robot speaker...'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to play voice: $e')),
                        );
                      }
                    },
            ),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Wait Until Finished Speaking', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          subtitle: const Text('Pauses the mission until the robot completely finishes talking', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          value: wait,
          activeThumbColor: AppColors.primary,
          onChanged: widget.readOnly
              ? null
              : (v) {
                  setState(() => widget.node.params['wait_completion'] = v);
                  widget.onChanged();
                },
        ),
      ],
    );
  }

  Widget _buildCallServiceInspector() {
    final outVar = widget.node.params['output_variable'] as String? ?? widget.node.params['variable_name'] as String? ?? '';
    return Column(
      children: [
        _buildTextField('Robot Service Name (Advanced)', 'service_name', '/set_mode'),
        const SizedBox(height: 12),
        _buildTextField('Service Message Type', 'service_type', 'std_srvs/srv/SetBool'),
        const SizedBox(height: 12),
        _buildTextField('Service Request Data (JSON, supports {variables})', 'payload', '{"data": true}', maxLines: 3),
        const SizedBox(height: 12),
        _buildVariableInputField(
          label: 'Save Service Response to Variable (Optional)',
          initialValue: outVar,
          hintText: 'e.g. service_result',
          prefixIcon: const Icon(Icons.data_object, size: 16),
          onChanged: (v) {
            final val = v.trim();
            widget.node.params['output_variable'] = val;
            widget.node.params['variable_name'] = val;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _buildNumberSlider(
          label: 'Wait limit for response (seconds)',
          value: (widget.node.params['timeout_sec'] as num?)?.toDouble() ?? 5.0,
          min: 1.0,
          max: 60.0,
          divisions: 59,
          onChanged: (v) {
            widget.node.params['timeout_sec'] = v;
            widget.onChanged();
          },
        ),
      ],
    );
  }

  Widget _buildCallActionInspector() {
    final outVar = widget.node.params['output_variable'] as String? ?? widget.node.params['variable_name'] as String? ?? '';
    return Column(
      children: [
        _buildTextField('Robot Action Goal Name (Advanced)', 'action_name', '/navigate_to_pose'),
        const SizedBox(height: 12),
        _buildTextField('Action Message Type', 'action_type', 'nav2_msgs/action/NavigateToPose'),
        const SizedBox(height: 12),
        _buildTextField('Goal Request Data (JSON, supports {variables})', 'payload', '{}', maxLines: 3),
        const SizedBox(height: 12),
        _buildVariableInputField(
          label: 'Save Action Result to Variable (Optional)',
          initialValue: outVar,
          hintText: 'e.g. action_result',
          prefixIcon: const Icon(Icons.data_object, size: 16),
          onChanged: (v) {
            final val = v.trim();
            widget.node.params['output_variable'] = val;
            widget.node.params['variable_name'] = val;
            widget.onChanged();
          },
        ),
        const SizedBox(height: 12),
        _buildNumberSlider(
          label: 'Wait limit for action (seconds)',
          value: (widget.node.params['timeout_sec'] as num?)?.toDouble() ?? 60.0,
          min: 1.0,
          max: 300.0,
          divisions: 29,
          onChanged: (v) {
            widget.node.params['timeout_sec'] = v;
            widget.onChanged();
          },
        ),
      ],
    );
  }

  Widget _buildPublishTopicInspector() {
    return Column(
      children: [
        _buildTextField('Broadcast Topic Name (Advanced)', 'topic_name', '/cmd_vel'),
        const SizedBox(height: 12),
        _buildTextField('Topic Message Type', 'message_type', 'geometry_msgs/msg/Twist'),
        const SizedBox(height: 12),
        _buildTextField('Message Data to Broadcast (JSON, supports {variables})', 'payload', '{}', maxLines: 3),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lightbulb_outline, size: 14, color: AppColors.primary),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  '💡 You can insert any previous variable into the topic message payload using {variable_name}.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRelocalizeInspector() {
    final mode = widget.node.params['mode'] as String? ?? 'global_scan';
    return DropdownButtonFormField<String>(
      key: ValueKey('${widget.node.id}_mode_$mode'),
      isExpanded: true,
      initialValue: ['global_scan', 'dock_seed'].contains(mode) ? mode : 'global_scan',
      dropdownColor: AppColors.surface,
      decoration: InputDecoration(
        labelText: 'How should the robot find its position?',
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.surfaceSunken,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius)),
      ),
      items: const [
        DropdownMenuItem(value: 'global_scan', child: Text('Laser Room Scan (Spin & find position)')),
        DropdownMenuItem(value: 'dock_seed', child: Text('Assume At Charger (Reset to charging dock)')),
      ],
      onChanged: widget.readOnly ? null : (v) {
        widget.node.params['mode'] = v;
        widget.onChanged();
      },
    );
  }

  Widget _buildJogMotionInspector() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildTextField('Drive Speed (m/s)', 'linear_vel', '0.0')),
            const SizedBox(width: 8),
            Expanded(child: _buildTextField('Turn Speed (rad/s)', 'angular_vel', '0.0')),
          ],
        ),
        const SizedBox(height: 12),
        _buildNumberSlider(
          label: 'How many seconds to drive',
          value: (widget.node.params['duration_sec'] as num?)?.toDouble() ?? 1.0,
          min: 0.1,
          max: 10.0,
          divisions: 99,
          onChanged: (v) {
            widget.node.params['duration_sec'] = v;
            widget.onChanged();
          },
        ),
      ],
    );
  }

  Widget _buildEmergencyStopInspector() {
    final sound = widget.node.params['sound_alert'] as bool? ?? true;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Sound Safety Alarm Buzzer', style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
      subtitle: const Text('Beep the robot onboard alarm buzzer while emergency stop is active', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      value: sound,
      activeThumbColor: AppColors.primary,
      onChanged: widget.readOnly ? null : (v) {
        setState(() => widget.node.params['sound_alert'] = v);
        widget.onChanged();
      },
    );
  }

  Widget _buildCancelNavigationInspector() {
    final haltType = widget.node.params['halt_type'] as String? ?? 'abort_goal';
    return DropdownButtonFormField<String>(
      key: ValueKey('${widget.node.id}_halt_$haltType'),
      isExpanded: true,
      initialValue: ['abort_goal', 'zero_vel'].contains(haltType) ? haltType : 'abort_goal',
      dropdownColor: AppColors.surface,
      decoration: InputDecoration(
        labelText: 'How to stop navigation',
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.surfaceSunken,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius)),
      ),
      items: const [
        DropdownMenuItem(value: 'abort_goal', child: Text('Cancel current driving goal smoothly')),
        DropdownMenuItem(value: 'zero_vel', child: Text('Instantly stop wheel motors immediately')),
      ],
      onChanged: widget.readOnly ? null : (v) {
        widget.node.params['halt_type'] = v;
        widget.onChanged();
      },
    );
  }

  Widget _buildTextField(String label, String paramKey, String defaultVal, {int maxLines = 1}) {
    return _buildVariableInputField(
      label: label,
      initialValue: widget.node.params[paramKey]?.toString() ?? defaultVal,
      maxLines: maxLines,
      onChanged: (v) {
        if (double.tryParse(v) != null && !v.contains('{') && !v.contains('[')) {
          widget.node.params[paramKey] = double.parse(v);
        } else {
          widget.node.params[paramKey] = v;
        }
        widget.onChanged();
      },
    );
  }

  Widget _buildNumberSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            Text(value.toStringAsFixed(1), style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          activeColor: AppColors.primary,
          inactiveColor: AppColors.borderStrong,
          onChanged: widget.readOnly ? null : onChanged,
        ),
      ],
    );
  }
}

class _VariableAwareTextField extends StatefulWidget {
  const _VariableAwareTextField({
    super.key,
    required this.initialValue,
    required this.onChanged,
    required this.labelText,
    this.hintText,
    this.helperText,
    this.prefixIcon,
    this.maxLines = 1,
    this.keyboardType,
    this.enabled = true,
    this.availableVariables = const [],
    this.onFocus,
  });

  final String initialValue;
  final ValueChanged<String> onChanged;
  final String labelText;
  final String? hintText;
  final String? helperText;
  final Widget? prefixIcon;
  final int maxLines;
  final TextInputType? keyboardType;
  final bool enabled;
  final List<AvailableVariable> availableVariables;
  final void Function(TextEditingController, FocusNode, ValueChanged<String>)? onFocus;

  @override
  State<_VariableAwareTextField> createState() => _VariableAwareTextFieldState();
}

class _VariableAwareTextFieldState extends State<_VariableAwareTextField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      widget.onFocus?.call(_controller, _focusNode, widget.onChanged);
    }
  }

  @override
  void didUpdateWidget(covariant _VariableAwareTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue && widget.initialValue != _controller.text) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _insertToken(String varName) {
    final token = '{$varName}';
    final text = _controller.text;
    final selection = _controller.selection;
    int start = selection.start;
    int end = selection.end;
    if (start < 0 || end < 0 || start > text.length || end > text.length) {
      start = text.length;
      end = text.length;
    }
    final newText = text.replaceRange(start, end, token);
    _controller.text = newText;
    final newPos = start + token.length;
    _controller.selection = TextSelection.collapsed(offset: newPos);
    widget.onChanged(newText);
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      maxLines: widget.maxLines,
      keyboardType: widget.keyboardType,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
      onTap: () {
        widget.onFocus?.call(_controller, _focusNode, widget.onChanged);
      },
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        helperText: widget.helperText,
        prefixIcon: widget.prefixIcon,
        suffixIcon: widget.availableVariables.isNotEmpty && widget.enabled
            ? PopupMenuButton<String>(
                tooltip: 'Insert Variable into ${widget.labelText}',
                icon: const Icon(Icons.data_object, size: 16, color: AppColors.primary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(maxHeight: 280, maxWidth: 260),
                color: AppColors.surfaceElevated,
                onSelected: (varName) => _insertToken(varName),
                itemBuilder: (ctx) => [
                  const PopupMenuItem<String>(
                    enabled: false,
                    height: 24,
                    child: Text(
                      'INSERT VARIABLE',
                      style: TextStyle(color: AppColors.textTertiary, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const PopupMenuDivider(height: 1),
                  for (final v in widget.availableVariables)
                    PopupMenuItem<String>(
                      value: v.name,
                      height: 32,
                      child: Row(
                        children: [
                          Icon(
                            v.isSystem ? Icons.memory : Icons.data_array,
                            size: 13,
                            color: v.isSystem ? AppColors.textSecondary : AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '{${v.name}}',
                              style: TextStyle(
                                color: v.isSystem ? AppColors.textPrimary : AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (v.isSystem)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceSunken,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('SYS', style: TextStyle(fontSize: 8, color: AppColors.textTertiary)),
                            ),
                        ],
                      ),
                    ),
                ],
              )
            : null,
        helperStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 10),
        hintStyle: const TextStyle(color: AppColors.textTertiary),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        filled: true,
        fillColor: AppColors.surfaceSunken,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.inputRadius), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      ),
      onChanged: (val) {
        widget.onChanged(val);
      },
    );
  }
}
