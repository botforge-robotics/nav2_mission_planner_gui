import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ros2_api/ros2_api.dart';

import '../providers/connection_provider.dart';
import '../providers/fleet_provider.dart';
import '../providers/robot_status.dart';
import '../providers/robot_telemetry_provider.dart';
import 'settings/fleet_settings_screen.dart';
import '../widgets/fleet/add_fleet_robot_dialog.dart';
import '../widgets/fleet/dispatch_fleet_task_dialog.dart';
import '../services/alerts_controller.dart';
import '../services/dock_pose_controller.dart';
import '../services/map_layers_controller.dart';
import '../services/mode_transition_tracker.dart';
import '../services/robot_connection_store.dart';
import '../services/sdk_api_service.dart';
import '../services/sdk_events_service.dart';
import '../services/sdk_state_service.dart' show SdkState;
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../utils/localize_at_dock.dart';
import '../services/zones_controller.dart';
import '../widgets/design/animated_metric.dart';

import '../widgets/design/fade_in.dart';
import '../widgets/design/status_pulse.dart';
import '../utils/push_with_telemetry.dart';
import '../widgets/map/not_localized_banner.dart';
import '../widgets/map/occupancy_grid_view.dart';
import '../widgets/sdk_state_builder.dart';
import 'dock/dock_charge_screen.dart';
import 'maps/map_view_screen.dart';
import 'maps/maps_list_screen.dart';
import 'maps/create_map_screen.dart';
import 'media/robot_media_screen.dart';
import 'missions/graph/ui_interaction_dialog.dart';

/// Reference §4 (Dashboard & Home). Core telemetry (battery, speed,
/// localization, dock) comes from direct rosbridge subscriptions via
/// ConnectionProvider/RobotTelemetryProvider — the app's connection whether
/// or not navpromini_sdk is running. Current map/mission status are an
/// optional enrichment polled from the SDK's /state endpoint (SdkStateService)
/// and show "—" rather than a guess when that poll isn't available — see
/// navpromini-sdk-is-optional-not-gateway in project memory.
///
/// Assumes it's built inside AppShell's connected subtree — RobotTelemetryProvider
/// is shared shell-wide (Locations/Missions/Teleop/Robot Status all read the
/// same instance) rather than each screen owning its own subscriptions.
///
/// Motion here is all state-driven, not decorative: the robot avatar's
/// pulse ring runs only while the robot is actually doing something (moving,
/// mapping, on a mission, charging); battery/speed glide between readings
/// instead of jump-cutting; cards settle in with a light stagger on first
/// load so the screen reads as "arriving" rather than popping in at once.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionProvider>();
    final robot = connection.robot;
    final ros2 = connection.ros2;
    if (!connection.isConnected || robot == null || ros2 == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    return _DashboardContent(
      connection: connection,
      robot: robot,
      ros2: ros2,
    );
  }
}

class _DashboardContent extends StatefulWidget {
  const _DashboardContent({
    required this.connection,
    required this.robot,
    required this.ros2,
  });

  final ConnectionProvider connection;
  final SavedRobot robot;
  final Ros2 ros2;

  @override
  State<_DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends State<_DashboardContent> {
  bool _isShowingUiInteraction = false;
  String? _lastShownInteractionId;
  Map<String, dynamic>? _activeRobotInteraction;

  void _checkUiInteraction(SdkState sdkState) {
    if (sdkState.missionStatus == 'waiting_for_user') {
      if (_isShowingUiInteraction) return;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _isShowingUiInteraction) return;
        _isShowingUiInteraction = true;
        try {
          final api = SdkApiService(widget.robot.ip);
          final inter = await api.fetchActiveUiInteraction();
          if (inter != null && mounted) {
            final p = inter['params'] as Map<String, dynamic>? ?? {};
            final subtype = (inter['subtype'] ?? p['subtype'] ?? '').toString().toLowerCase();
            final target = (inter['target'] ?? p['target'] ?? 'robot_screen').toString().toLowerCase();

            // Browser node (and any prompt targeted at the robot screen) MUST ONLY run
            // on the robot screen UI, never taking over the Mission Planner dashboard.
            // Mission Planner continues displaying mission progress.
            if (subtype == 'browser' || target == 'robot_screen') {
              if (_activeRobotInteraction?['interaction_id'] != inter['interaction_id']) {
                setState(() => _activeRobotInteraction = inter);
              }
              _isShowingUiInteraction = false;
              return;
            }

            final id = inter['interaction_id']?.toString() ?? inter['node_id']?.toString() ?? '';
            if (id.isNotEmpty && id != _lastShownInteractionId) {
              _lastShownInteractionId = id;
              await UiInteractionDialog.show(
                context,
                api: api,
                interaction: inter,
                onDismissed: () {
                  if (mounted) {
                    setState(() => _isShowingUiInteraction = false);
                  }
                },
              );
              return;
            }
          }
        } catch (_) {}
        if (mounted) {
          setState(() => _isShowingUiInteraction = false);
        }
      });
    } else {
      if (_activeRobotInteraction != null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _activeRobotInteraction != null) {
            setState(() => _activeRobotInteraction = null);
          }
        });
      }
      _lastShownInteractionId = null;
      _isShowingUiInteraction = false;
    }
  }

  Widget _buildRobotScreenActiveBanner() {
    final inter = _activeRobotInteraction;
    final p = inter?['params'] as Map<String, dynamic>? ?? {};
    final title = inter?['title']?.toString() ?? p['title']?.toString() ?? 'Web Browser';
    final subtype = (inter?['subtype'] ?? p['subtype'] ?? 'browser').toString().toLowerCase();
    final isBrowser = subtype == 'browser';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isBrowser ? const Color(0xFFF0FDFA) : const Color(0xFFFFF3EE),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(
          color: isBrowser ? const Color(0xFF99F6E4) : const Color(0xFFFFD4C2),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isBrowser ? const Color(0xFF0D9488) : AppColors.primary).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isBrowser ? Icons.language_rounded : Icons.tablet_mac_rounded,
              color: isBrowser ? const Color(0xFF0D9488) : AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isBrowser ? 'Mission In Progress: Web Browser on Robot Screen' : 'Active on Robot Screen ($subtype)',
                      style: TextStyle(
                        color: isBrowser ? const Color(0xFF0F766E) : AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isBrowser ? const Color(0xFF0D9488) : AppColors.primary).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'ROBOT SCREEN',
                        style: TextStyle(
                          color: isBrowser ? const Color(0xFF0D9488) : AppColors.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  isBrowser
                      ? 'The robot is currently presenting "$title" on its physical touchscreen. Mission will automatically advance once closed on the robot.'
                      : 'Awaiting physical interaction on the robot screen terminal.',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
          if (isBrowser)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                side: const BorderSide(color: Color(0xFF0D9488)),
                foregroundColor: const Color(0xFF0D9488),
              ),
              icon: const Icon(Icons.skip_next_rounded, size: 16),
              label: const Text('Bypass Step', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              onPressed: () async {
                final id = inter?['interaction_id']?.toString() ?? inter?['node_id']?.toString() ?? '';
                if (id.isNotEmpty) {
                  try {
                    await SdkApiService(widget.robot.ip).submitUiResponse(id, action: 'closed');
                  } catch (_) {}
                }
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final telemetry = context.watch<RobotTelemetryProvider>();
    final isDesktop = Breakpoints.of(context) == DeviceClass.desktop;

    final fleet = context.watch<FleetProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(fleet.isFleetMode ? 'Fleet Dashboard' : 'Dashboard'),
        actions: [
          if (fleet.isFleetMode) ...[
            IconButton(
              icon: const Icon(Icons.settings_suggest_rounded, color: Colors.blue),
              tooltip: 'Manage Fleet & Robots',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FleetSettingsScreen()),
                );
              },
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.perm_media_outlined),
              tooltip: 'Robot Media & Signage (DND)',
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const RobotMediaScreen(),
                ));
              },
            ),
            _AppBarBatteryWidget(telemetry: telemetry),
          ],
        ],
      ),
      body: SafeArea(
        child: SdkStateBuilder(
          robotIp: widget.robot.ip,
          builder: (context, sdkState) {
            _checkUiInteraction(sdkState);
            final battery = telemetry.batteryPercentage;
            final charging =
                telemetry.chargeStatus == ChargeStatus.charging ||
                    telemetry.chargeStatus == ChargeStatus.full;

            if (isDesktop) {
              return Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column (flex: 6): Robot Hero & Large Live Map
                    Expanded(
                      flex: 6,
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          if (_activeRobotInteraction != null) ...[
                            _buildRobotScreenActiveBanner(),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                          if (battery != null &&
                              battery <= 15 &&
                              !charging) ...[
                            _LowBatteryBanner(percentage: battery),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                          _RobotCard(
                              robot: widget.robot,
                              telemetry: telemetry,
                              sdkState: sdkState),
                          const SizedBox(height: AppSpacing.lg),
                          _DashboardTasksOverviewCard(robotIp: widget.robot.ip),
                          const SizedBox(height: AppSpacing.lg),
                          _MapPreviewCard(
                            ros2: widget.ros2,
                            mapName: sdkState.mapName,
                            sdkMode: sdkState.mode,
                            robotIp: widget.robot.ip,
                            height: 440,
                            interactive: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xl),
                    // Right Column (flex: 4): Telemetry Grid & Alerts Stream
                    Expanded(
                      flex: 4,
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          _StatGridDesktop(
                              telemetry: telemetry, sdkState: sdkState),
                          const SizedBox(height: AppSpacing.lg),
                          _AlertsCard(robotIp: widget.robot.ip),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            var step = 0;
            Duration nextDelay() =>
                Duration(milliseconds: 60 * step++);

            return CenteredFormColumn(
              maxWidth: 720,
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  if (_activeRobotInteraction != null) ...[
                    _buildRobotScreenActiveBanner(),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  if (battery != null && battery <= 15 && !charging) ...[
                    FadeSlideIn(
                      delay: nextDelay(),
                      child: _LowBatteryBanner(percentage: battery),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  FadeSlideIn(
                    delay: nextDelay(),
                    child: _RobotCard(
                        robot: widget.robot,
                        telemetry: telemetry,
                        sdkState: sdkState),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FadeSlideIn(
                    delay: nextDelay(),
                    child: _DashboardTasksOverviewCard(robotIp: widget.robot.ip),
                  ),
                  if (!fleet.isFleetMode) ...[
                    const SizedBox(height: AppSpacing.lg),
                    FadeSlideIn(
                      delay: nextDelay(),
                      child: _StatRow(
                          telemetry: telemetry, sdkState: sdkState),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  FadeSlideIn(
                    delay: nextDelay(),
                    child: _MapPreviewCard(
                        ros2: widget.ros2,
                        mapName: sdkState.mapName,
                        sdkMode: sdkState.mode,
                        robotIp: widget.robot.ip),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FadeSlideIn(
                    delay: nextDelay(),
                    child: _AlertsCard(robotIp: widget.robot.ip),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Whether [status] represents the robot actively doing something right now
/// — the one signal that drives every "live" pulse on this screen (the
/// avatar's ring, the status dot). An idle or fully-charged robot gets a
/// still indicator; there's nothing happening to announce.
bool _isActiveStatus(RobotStatus status) => switch (status) {
      RobotStatus.moving ||
      RobotStatus.mapping ||
      RobotStatus.missionInProgress ||
      RobotStatus.charging =>
        true,
      RobotStatus.idle || RobotStatus.charged => false,
    };

/// A short, honest status line under the name — real per [status], not the
/// reference mockup's fixed "Ready to go" caption.
String _subtitleFor(RobotStatus status) => switch (status) {
      RobotStatus.idle => 'Ready to go',
      RobotStatus.charging => 'Charging at the dock',
      RobotStatus.charged => 'Fully charged',
      RobotStatus.moving => 'On the move',
      RobotStatus.mapping => 'Mapping in progress',
      RobotStatus.missionInProgress => 'Mission in progress',
    };

/// Reference §4's home card: name and status on the left, a large robot
/// graphic on the right, battery as its own row underneath. Purely
/// informational now — no tap target here. The two destinations this card
/// used to open (Robot Status, Dock & Charge) moved to a summary card at the
/// top of Settings instead; see SettingsHomeScreen's _RobotSummaryCard.
class _RobotCard extends StatelessWidget {
  const _RobotCard(
      {required this.robot, required this.telemetry, required this.sdkState});

  final SavedRobot robot;
  final RobotTelemetryProvider telemetry;
  final SdkState sdkState;

  @override
  Widget build(BuildContext context) {
    final battery = telemetry.batteryPercentage;
    final status = deriveRobotStatus(telemetry: telemetry, sdkState: sdkState);
    final charging = telemetry.chargeStatus == ChargeStatus.charging ||
        telemetry.chargeStatus == ChargeStatus.full;
    final isActive = _isActiveStatus(status);

    final fleet = context.watch<FleetProvider>();

    if (fleet.isFleetMode) {
      final robots = fleet.robots;
      final tasks = fleet.activeMissions;

      final onlineCount = robots.where((r) => r.isActive || r.status == 'active' || r.status == 'ready' || r.status == 'moving').length;
      final offlineCount = robots.length - onlineCount;
      final chargingCount = robots.where((r) => r.isCharging).length;

      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'NavPro Mini Fleet',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${robots.length} AMRS',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$onlineCount Online · $offlineCount Offline · $chargingCount Charging · ${tasks.length} In-Flight Tasks',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () => AddFleetRobotDialog.show(context),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Add Robot'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.sm),
              // Open-RMF style Fleet Robots Table
              if (robots.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No robots registered in fleet yet. Tap "+ Add Robot" to commission an AMR.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: constraints.maxWidth),
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                              Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.grey.shade100,
                            ),
                            dataRowMinHeight: 48,
                            dataRowMaxHeight: 56,
                            columnSpacing: 24,
                            columns: const [
                              DataColumn(label: Text('ROBOT NAME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                              DataColumn(label: Text('STATUS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                              DataColumn(label: Text('BATTERY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                              DataColumn(label: Text('LEVEL / DOCK', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                              DataColumn(label: Text('CURRENT TASK', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                            ],
                            rows: robots.map((r) {
                              final ip = fleet.getRobotIp(r.id) ?? r.ip;
                              final isOnline = r.isActive || r.status == 'active' || r.status == 'ready' || r.status == 'moving';
                              final isCharging = r.isCharging;
                              final currentTask = tasks.where((t) => t['robot'] == r.name || t['robot_id'] == r.id).firstOrNull;
                              final taskDesc = currentTask != null
                                  ? (currentTask['type'] ?? currentTask['task_type'] ?? 'Mission')
                                  : (isCharging ? 'Recharging' : (isOnline ? 'Idle / Standby' : 'Offline'));
                              final levelObj = fleet.levels.where((l) => l.id == r.levelId || l.name == r.levelId).firstOrNull;
                              final levelDisplay = levelObj?.name ?? (r.levelName != null && r.levelName!.isNotEmpty ? r.levelName! : null) ?? 'Level 1';

                              return DataRow(
                                cells: [
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircleAvatar(
                                          radius: 14,
                                          backgroundColor: isOnline ? Colors.blue.shade50 : Colors.grey.shade200,
                                          child: Icon(Icons.smart_toy_rounded, size: 16, color: isOnline ? Colors.blue : Colors.grey),
                                        ),
                                        const SizedBox(width: 8),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(r.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                            Text(ip != null ? 'IP: $ip' : r.serial, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isCharging
                                            ? Colors.amber.shade100
                                            : (isOnline ? Colors.green.shade100 : Colors.grey.shade200),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isCharging ? 'CHARGING' : (isOnline ? 'ONLINE' : 'OFFLINE'),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isCharging
                                              ? Colors.amber.shade900
                                              : (isOnline ? Colors.green.shade900 : Colors.grey.shade700),
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isCharging
                                              ? Icons.bolt_rounded
                                              : ((r.batteryPercent ?? 100) <= 20
                                                  ? Icons.battery_alert_rounded
                                                  : Icons.battery_full_rounded),
                                          size: 16,
                                          color: isCharging
                                              ? Colors.amber.shade800
                                              : ((r.batteryPercent ?? 100) <= 20 ? Colors.red : Colors.green),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          r.batteryPercent != null ? '${r.batteryPercent!.round()}%' : '—',
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      '$levelDisplay · ${r.dockWaypoint ?? "dock"}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  DataCell(
                                    Container(
                                      constraints: const BoxConstraints(maxWidth: 160),
                                      child: Text(
                                        taskDesc.toString(),
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: currentTask != null ? Colors.blue : Colors.grey.shade700,
                                          fontWeight: currentTask != null ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      );
    }

    return ValueListenableBuilder<String?>(
      valueListenable: ModeTransitionTracker.instance.transitioningTo,
      builder: (context, transitioningTo, _) {
        final isStopping =
            transitioningTo == 'idle' || transitioningTo == 'navigation';
        final statusLabel = isStopping ? 'STOPPING MAPPING…' : status.label;
        final statusColor = isStopping ? AppColors.warning : status.color;
        final livePulse = isStopping || isActive;
        final subtitle = isStopping
            ? 'Cleaning up SLAM session on robot…'
            : _subtitleFor(status);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(robot.name,
                              style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              StatusPulseDot(
                                  color: statusColor, live: livePulse, size: 8),
                              const SizedBox(width: 6),
                              AnimatedSwitcher(
                                duration: AppMotion.fast,
                                child: Text(
                                  'Online · $statusLabel',
                                  key: ValueKey('${status}_$isStopping'),
                                  style: const TextStyle(
                                      color: AppColors.textSecondary),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          AnimatedSwitcher(
                            duration: AppMotion.fast,
                            child: Text(
                              subtitle,
                              key: ValueKey('subtitle-$status-$isStopping'),
                              style: const TextStyle(
                                  color: AppColors.textTertiary, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                // The robot's real product photo (assets/robot_photo.png) —
                // shown directly on the card's own surface rather than
                // inside a colored tile, since the photo is already a
                // considered, self-contained image (transparent background,
                // real shadow/lighting) that a colored backdrop would only
                // compete with.
                Image.asset('assets/robot_photo.png',
                    width: 84, height: 84, fit: BoxFit.contain),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Text('Battery', style: Theme.of(context).textTheme.bodyMedium),
                const Spacer(),
                Icon(
                  charging ? Icons.bolt_rounded : Icons.battery_full_rounded,
                  size: 16,
                  color: charging ? AppColors.success : AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                AnimatedMetricText(
                  value: battery,
                  formatter: (v) => telemetry.formatBatteryPercent(),
                  style: AppTextStyles.metricSmall,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            AnimatedMetricBar(
              value: battery != null ? battery / 100 : 0,
              backgroundColor: AppColors.border,
              color: charging ? AppColors.success : AppColors.primary,
            ),
          ],
        ),
      ),
    );
      },
    );
  }
}

/// Open-RMF Task Overview Table on Dashboard displaying active, queued, scheduled, and history tasks
class _DashboardTasksOverviewCard extends StatefulWidget {
  const _DashboardTasksOverviewCard({required this.robotIp});

  final String robotIp;

  @override
  State<_DashboardTasksOverviewCard> createState() => _DashboardTasksOverviewCardState();
}

class _DashboardTasksOverviewCardState extends State<_DashboardTasksOverviewCard> {
  String _taskFilter = 'all'; // 'all', 'active', 'queued', 'scheduled', 'history'
  Timer? _refreshTimer;
  List<Map<String, dynamic>> _schedules = [];

  @override
  void initState() {
    super.initState();
    _loadLocalTasks();
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) _loadLocalTasks();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLocalTasks() async {
    try {
      final api = SdkApiService(widget.robotIp);
      final list = await api.listSchedules();
      if (mounted) {
        setState(() => _schedules = list);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final fleet = context.watch<FleetProvider>();

    // Build unified tasks list
    final List<Map<String, dynamic>> allTasks = [];

    // 1. Fleet tasks from Open-RMF
    for (final t in fleet.activeMissions) {
      final status = (t['state'] ?? t['status'] ?? 'active').toString().toLowerCase();
      String group = 'active';
      if (status == 'pending' || status == 'queued' || status == 'standby' || status == 'paused') {
        group = 'queued';
      } else if (status == 'completed' || status == 'succeeded' || status == 'failed' || status == 'canceled' || status == 'cancelled') {
        group = 'history';
      }
      final isCancelled = status == 'canceled' || status == 'cancelled' || status == 'failed';
      final isCompleted = status == 'completed' || status == 'succeeded';
      allTasks.add({
        'id': t['id']?.toString() ?? 'task_${allTasks.length}',
        'name': t['type'] ?? t['task_type'] ?? t['name'] ?? 'RMF Task',
        'robot': t['robot'] ?? t['robot_id'] ?? 'AMR',
        'status': status,
        'group': group,
        'progress': isCancelled ? 0.0 : ((t['progress'] as num?)?.toDouble() ?? (isCompleted ? 1.0 : 0.4)),
        'time': t['start_time'] ?? t['timestamp'] ?? 'Active',
      });
    }

    // 2. Schedules
    for (final s in _schedules) {
      final enabled = s['enabled'] != false;
      allTasks.add({
        'id': s['id']?.toString() ?? 'sched_${allTasks.length}',
        'name': s['mission_name'] ?? s['name'] ?? 'Scheduled Task',
        'robot': s['robot'] ?? 'Assigned AMR',
        'status': enabled ? 'scheduled' : 'disabled',
        'group': 'scheduled',
        'progress': 0.0,
        'time': s['time'] ?? s['cron'] ?? 'Scheduled',
      });
    }

    // Filter tasks
    final filteredTasks = _taskFilter == 'all'
        ? allTasks
        : allTasks.where((t) => t['group'] == _taskFilter).toList();

    final activeCount = allTasks.where((t) => t['group'] == 'active').length;
    final queuedCount = allTasks.where((t) => t['group'] == 'queued').length;
    final scheduledCount = allTasks.where((t) => t['group'] == 'scheduled').length;
    final historyCount = allTasks.where((t) => t['group'] == 'history').length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.table_chart_outlined, size: 20, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Tasks Overview',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${allTasks.length} TASKS',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue),
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: () => DispatchFleetTaskDialog.show(context),
                  icon: const Icon(Icons.send_rounded, size: 14),
                  label: const Text('Dispatch Task', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Filter chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip('all', 'All (${allTasks.length})', null),
                  const SizedBox(width: AppSpacing.xs),
                  _chip('active', 'Active ($activeCount)', AppColors.stateExecuting),
                  const SizedBox(width: AppSpacing.xs),
                  _chip('queued', 'Queued ($queuedCount)', AppColors.warning),
                  const SizedBox(width: AppSpacing.xs),
                  _chip('scheduled', 'Scheduled ($scheduledCount)', const Color(0xFFB388FF)),
                  const SizedBox(width: AppSpacing.xs),
                  _chip('history', 'History ($historyCount)', AppColors.textSecondary),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            if (filteredTasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    _taskFilter == 'all'
                        ? 'No tasks in system. Dispatch a task to send an AMR on a mission.'
                        : 'No ${_taskFilter.toUpperCase()} tasks found.',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: constraints.maxWidth),
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(
                            Theme.of(context).brightness == Brightness.dark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.grey.shade100,
                          ),
                          dataRowMinHeight: 44,
                          dataRowMaxHeight: 52,
                          columnSpacing: 20,
                          columns: const [
                            DataColumn(label: Text('TASK NAME / ID', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                            DataColumn(label: Text('ROBOT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                            DataColumn(label: Text('STATUS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                            DataColumn(label: Text('PROGRESS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                            DataColumn(label: Text('TIME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                            DataColumn(label: Text('ACTION', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                          ],
                          rows: filteredTasks.map((t) {
                            final status = t['status'] as String;
                            final group = t['group'] as String;
                            final progress = (t['progress'] as double?) ?? 0.0;
                            Color statusColor = Colors.grey;
                            if (group == 'active') statusColor = Colors.blue;
                            if (group == 'queued') statusColor = Colors.amber;
                            if (group == 'scheduled') statusColor = const Color(0xFFB388FF);
                            if (status == 'completed' || status == 'succeeded') statusColor = Colors.green;
                            if (status == 'failed' || status == 'canceled' || status == 'cancelled') statusColor = Colors.red;

                            return DataRow(
                              cells: [
                                DataCell(
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(t['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                      Text(t['id'] as String, style: const TextStyle(fontSize: 10, color: AppColors.textTertiary)),
                                    ],
                                  ),
                                ),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.smart_toy_outlined, size: 14, color: Colors.blue),
                                      const SizedBox(width: 4),
                                      Text(t['robot'] as String, style: const TextStyle(fontSize: 12)),
                                    ],
                                  ),
                                ),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      status.toUpperCase(),
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  SizedBox(
                                    width: 80,
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      backgroundColor: Colors.grey.withValues(alpha: 0.2),
                                      valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(t['time'] as String, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                ),
                                DataCell(
                                  (group == 'active' || group == 'queued')
                                      ? IconButton(
                                          icon: const Icon(Icons.cancel_outlined, size: 16, color: AppColors.danger),
                                          tooltip: 'Cancel task',
                                          onPressed: () async {
                                            await fleet.cancelRmfTask(t['id'] as String);
                                            setState(() {});
                                          },
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String key, String label, Color? color) {
    final isSelected = _taskFilter == key;
    return ChoiceChip(
      selected: isSelected,
      onSelected: (val) {
        if (val) setState(() => _taskFilter = key);
      },
      avatar: color != null
          ? StatusPulseDot(
              color: color,
              live: key == 'active',
              size: 8,
            )
          : null,
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}

/// Two cards only — Speed and Mission — not the earlier four-tile grid
/// (mode and current map now live in the robot card's status badge / the
/// map preview header instead of being repeated here).
class _StatRow extends StatelessWidget {
  const _StatRow({required this.telemetry, required this.sdkState});

  final RobotTelemetryProvider telemetry;
  final SdkState sdkState;

  @override
  Widget build(BuildContext context) {
    final fleet = context.watch<FleetProvider>();

    if (fleet.isFleetMode) {
      return Row(
        children: [
          Expanded(
            child: _Stat(
              icon: Icons.smart_toy_rounded,
              label: 'Fleet Robots',
              value: Text(
                '${fleet.robots.length} Units',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _Stat(
              icon: Icons.alt_route_rounded,
              label: 'Active Tasks',
              value: Text(
                '${fleet.activeMissions.length} In-Flight',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: _Stat(
            icon: Icons.speed_rounded,
            label: 'Speed',
            value: AnimatedMetricText(
              value: telemetry.linearSpeedMps?.abs(),
              formatter: (v) => '${v.toStringAsFixed(2)} m/s',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _Stat(
            icon: Icons.flag_rounded,
            label: 'Mission Progress',
            value: AnimatedSwitcher(
              duration: AppMotion.fast,
              child: Text(
                sdkState.missionStatus == 'paused' &&
                        sdkState.pauseReason == 'low_battery'
                    ? 'PAUSED (CHARGING)'
                    : (sdkState.missionStatus?.toUpperCase() ?? '—'),
                key: ValueKey(
                    '${sdkState.missionStatus}_${sdkState.pauseReason}'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: sdkState.missionStatus == 'paused' &&
                              sdkState.pauseReason == 'low_battery'
                          ? AppColors.warning
                          : null,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

void _showLocalizationActionSheet(BuildContext context,
    {required SdkApiService api}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.my_location_rounded,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Robot Localization',
                    style:
                        Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Seed or reset AMCL belief of the robot position:',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.ev_station_rounded,
                      color: AppColors.accent, size: 22),
                ),
                title: const Text('Robot at Dock',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text(
                    'Seed AMCL pose from known docking station coordinates',
                    style: TextStyle(fontSize: 12)),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final messenger = ScaffoldMessenger.of(context);
                  messenger.showSnackBar(
                    const SnackBar(
                        content:
                            Text('Seeding AMCL pose from dock station...')),
                  );
                  final ok = await localizeAtDock(context: context, api: api);
                  if (ok) {
                    messenger.showSnackBar(
                      const SnackBar(
                          content:
                              Text('Successfully localized robot at dock.')),
                    );
                  }
                },
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.pin_drop_rounded,
                      color: AppColors.primary, size: 22),
                ),
                title: const Text('Set 2D Pose on Map',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text(
                    'Tap & drag robot heading directly on the interactive map',
                    style: TextStyle(fontSize: 12)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const MapViewScreen(initialPosePicking: true),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.sync_rounded,
                      color: AppColors.accent, size: 22),
                ),
                title: const Text('Auto-Relocalize (360° Spin)',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text(
                    'Autonomous in-place rotation to disperse and converge particles',
                    style: TextStyle(fontSize: 12)),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final messenger = ScaffoldMessenger.of(context);
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Starting autonomous 360° relocalization spin…'),
                      duration: Duration(seconds: 4),
                    ),
                  );
                  try {
                    final res = await api.recoverRelocalization();
                    final converged = res['converged'] == true;
                    messenger.showSnackBar(SnackBar(
                      content: Text(converged
                          ? 'Relocalized successfully! AMCL particles converged.'
                          : '360° spin finished. Check robot pose on map.'),
                      backgroundColor: converged ? AppColors.success : null,
                    ));
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(
                        content: Text('Auto-relocalization failed: $e')));
                  }
                },
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.radar_rounded,
                      color: AppColors.warning, size: 22),
                ),
                title: const Text('Global Relocalization',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text(
                    'Disperse particles across entire map; drive to converge',
                    style: TextStyle(fontSize: 12)),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final messenger = ScaffoldMessenger.of(context);
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Global relocalization initiated. Jog robot to let particles converge.'),
                      duration: Duration(seconds: 4),
                    ),
                  );
                  try {
                    await api.reinitializeGlobalLocalization();
                  } catch (e) {
                    messenger.showSnackBar(SnackBar(
                        content: Text('Relocalization request error: $e')));
                  }
                },
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      );
    },
  );
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Widget value;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          value,
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );

    if (onTap != null) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: body,
        ),
      );
    }

    return Card(child: body);
  }
}

class _StatGridDesktop extends StatelessWidget {
  const _StatGridDesktop({required this.telemetry, required this.sdkState});

  final RobotTelemetryProvider telemetry;
  final SdkState sdkState;

  @override
  Widget build(BuildContext context) {
    final fleet = context.watch<FleetProvider>();

    if (fleet.isFleetMode) {
      final robots = fleet.robots;
      final onlineCount = robots.where((r) => r.isActive || r.status == 'active' || r.status == 'ready' || r.status == 'moving').length;
      final chargingCount = robots.where((r) => r.isCharging).length;

      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _Stat(
                  icon: Icons.smart_toy_rounded,
                  label: 'Online AMRs',
                  value: Text(
                    '$onlineCount / ${robots.length} Online',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _Stat(
                  icon: Icons.alt_route_rounded,
                  label: 'In-Flight Tasks',
                  value: Text(
                    '${fleet.activeMissions.length} Active',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  icon: Icons.layers_rounded,
                  label: 'Building Levels',
                  value: Text(
                    '${fleet.levels.length} Floors',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _Stat(
                  icon: Icons.battery_charging_full_rounded,
                  label: 'Charging Docks',
                  value: Text(
                    '$chargingCount Charging',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _Stat(
                icon: Icons.speed_rounded,
                label: 'Linear Speed',
                value: AnimatedMetricText(
                  value: telemetry.linearSpeedMps?.abs(),
                  formatter: (v) => '${v.toStringAsFixed(2)} m/s',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _Stat(
                icon: Icons.flag_rounded,
                label: 'Mission Status',
                value: Text(
                  sdkState.missionStatus == 'paused' &&
                          sdkState.pauseReason == 'low_battery'
                      ? 'PAUSED (CHARGING)'
                      : (sdkState.missionStatus?.toUpperCase() ?? 'IDLE'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: sdkState.missionStatus == 'paused' &&
                                sdkState.pauseReason == 'low_battery'
                            ? AppColors.warning
                            : null,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _Stat(
                icon: Icons.my_location_rounded,
                label: 'AMCL Localization',
                trailing: const Icon(Icons.touch_app_rounded,
                    size: 14, color: AppColors.textTertiary),
                onTap: () {
                  final ip = context.read<ConnectionProvider>().robot?.ip;
                  if (ip != null) {
                    _showLocalizationActionSheet(context,
                        api: SdkApiService(ip));
                  }
                },
                value: Row(
                  children: [
                    Expanded(
                      child: Text(
                        telemetry.localized
                            ? (telemetry.localizationHealth == 'degraded'
                                ? 'DEGRADED'
                                : 'LOCALIZED')
                            : (sdkState.mode == 'navigation'
                                ? 'UNLOCALIZED'
                                : 'OFF (IDLE)'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: !telemetry.localized
                              ? (sdkState.mode == 'navigation'
                                  ? AppColors.danger
                                  : AppColors.textTertiary)
                              : (telemetry.localizationHealth == 'degraded'
                                  ? AppColors.warning
                                  : AppColors.success),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded,
                        size: 11, color: AppColors.textTertiary),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _Stat(
                icon: Icons.dock_rounded,
                label: 'Dock State',
                value: Text(
                  telemetry.dockStatus?.toUpperCase() ?? 'UNDOCKED',
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ],
    );

  }
}

class _MapPreviewCard extends StatefulWidget {
  const _MapPreviewCard({
    required this.ros2,
    required this.mapName,
    required this.robotIp,
    this.sdkMode,
    this.height = 140,
    this.interactive = false,
  });

  final Ros2 ros2;
  final String? mapName;
  final String? sdkMode;
  final String robotIp;
  final double height;
  final bool interactive;

  @override
  State<_MapPreviewCard> createState() => _MapPreviewCardState();
}

class _MapPreviewCardState extends State<_MapPreviewCard> {
  ({double x, double y, double theta})? _dockPose;
  bool _gridLoaded = false;
  bool _enableInteractions = false;

  @override
  void initState() {
    super.initState();
    DockPoseController.instance.addListener(_onDockPoseChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDockPose();
      DockPoseController.instance.refresh(SdkApiService(widget.robotIp));
      ZonesController.instance
          .refresh(SdkApiService(widget.robotIp), map: widget.mapName);
    });
  }

  void _onDockPoseChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    DockPoseController.instance.removeListener(_onDockPoseChanged);
    super.dispose();
  }

  Future<void> _loadDockPose() async {
    final dock = await fetchDockPose(SdkApiService(widget.robotIp));
    if (!mounted || dock == null) return;
    setState(() => _dockPose = dock);
  }

  /// True when SLAM is active — map publishes live even without a saved map name.
  bool get _isMappingActive => widget.sdkMode == 'mapping';

  /// True when Nav2 navigation is actively running with an active map or when a grid has been received.
  bool get _isNavigating =>
      _gridLoaded ||
      widget.sdkMode == 'navigation' ||
      (widget.mapName != null &&
          widget.mapName!.isNotEmpty &&
          widget.mapName != 'default');

  @override
  Widget build(BuildContext context) {
    final telemetry = context.watch<RobotTelemetryProvider>();
    final fleet = context.watch<FleetProvider>();
    final api = SdkApiService(widget.robotIp);

    return ValueListenableBuilder<String?>(
      valueListenable: ModeTransitionTracker.instance.transitioningTo,
      builder: (context, transitioningTo, _) {
        final isStoppingMapping =
            transitioningTo == 'idle' || transitioningTo == 'navigation';
        final isCurrentlyMapping = _isMappingActive && !isStoppingMapping;
        final hasActiveNav = _isNavigating && !isStoppingMapping;
        final showNoActiveMap = !isStoppingMapping && !isCurrentlyMapping && !hasActiveNav;

        // Derive card title
        final String title = isStoppingMapping
            ? 'Stopping mapping…'
            : (isCurrentlyMapping
                ? 'Mapping in progress…'
                : (hasActiveNav
                    ? (widget.mapName != null && widget.mapName!.isNotEmpty
                        ? widget.mapName!
                        : 'Active Map')
                    : 'Map'));

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    if (fleet.isFleetMode && fleet.levels.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceSunken,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isDense: true,
                            value: (fleet.selectedLevel != null && fleet.levels.any((l) => l.id == fleet.selectedLevel!.id))
                                ? fleet.selectedLevel!.id
                                : fleet.levels.first.id,
                            icon: const Icon(Icons.arrow_drop_down_rounded, size: 20),
                            items: fleet.levels.map((lvl) {
                              return DropdownMenuItem<String>(
                                value: lvl.id,
                                child: Text(
                                  lvl.name,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              );
                            }).toList(),
                            onChanged: (newLevelId) {
                              if (newLevelId != null) {
                                fleet.selectLevel(newLevelId);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                    if (widget.interactive)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: _enableInteractions
                            ? 'Map zoom/pan unlocked (wheel zooms map). Click to lock.'
                            : 'Map zoom/pan locked (wheel scrolls page). Click to interact with map.',
                        icon: Icon(
                          _enableInteractions ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                          size: 18,
                          color: _enableInteractions ? AppColors.accent : AppColors.textTertiary,
                        ),
                        onPressed: () => setState(() => _enableInteractions = !_enableInteractions),
                      ),
                    if (isCurrentlyMapping)
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const CreateMapScreen()),
                        ),
                        child: const Text('Resume Mapping'),
                      )
                    else if (hasActiveNav)
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const MapViewScreen()),
                        ),
                        child: const Text('Open Map'),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
                  child: Container(
                    height: widget.height,
                    width: double.infinity,
                    color: AppColors.surfaceSunken,
                    child: isStoppingMapping
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  Text(
                                    'Stopping mapping session…',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Shutting down SLAM on robot. This takes a few seconds.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Stack(
                            children: [
                              Positioned.fill(
                                child: ValueListenableBuilder<
                                    Set<MapLayer>>(
                                  valueListenable:
                                      MapLayersController.instance,
                                  builder: (context, visibleLayers, _) =>
                                      OccupancyGridView(
                                    ros2: widget.ros2,
                                    interactive: widget.interactive && _enableInteractions,
                                    isMapping: isCurrentlyMapping,
                                    showDock: visibleLayers
                                        .contains(MapLayer.dock),
                                    showPath: visibleLayers
                                        .contains(MapLayer.path),
                                    showLaserScan: visibleLayers
                                        .contains(MapLayer.laserScan),
                                    initialPose: telemetry.rawPose ??
                                        telemetry.rawOdomPose,
                                    initialPath: telemetry.currentPath,
                                    showGlobalCostmap: visibleLayers
                                        .contains(MapLayer.globalCostmap),
                                    showLocalCostmap: visibleLayers
                                        .contains(MapLayer.localCostmap),
                                    dockPoseOverride: DockPoseController.instance.value.dock ?? _dockPose,
                                    standoffPoseOverride: DockPoseController.instance.value.standoff,
                                    zones: visibleLayers.contains(MapLayer.zones)
                                        ? ZonesController.instance.value
                                        : const [],
                                    showZones: visibleLayers.contains(MapLayer.zones),
                                    showLocalizationBadge: false,

                                    onMapLoaded: (_) {
                                      if (mounted && !_gridLoaded) {
                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                          if (mounted && !_gridLoaded) {
                                            setState(() => _gridLoaded = true);
                                          }
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ),
                              if (showNoActiveMap && !_gridLoaded)
                                Positioned.fill(
                                  child: Container(
                                    color: Theme.of(context).cardColor,
                                    child: _NoActiveMapPrompt(robotIp: widget.robotIp),
                                  ),
                                ),
                              if (!telemetry.localized && hasActiveNav && !showNoActiveMap)
                                    Positioned(
                                      left: AppSpacing.xs,
                                      right: AppSpacing.xs,
                                      top: AppSpacing.xs,
                                      child: NotLocalizedBanner(
                                        api: api,
                                        onDecline: () {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: const Text(
                                                  'Open Map to set the initial pose.'),
                                              action: SnackBarAction(
                                                label: 'Open Map',
                                                onPressed: () =>
                                                    Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        const MapViewScreen(
                                                            initialPosePicking:
                                                                true),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                ],
                              ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Shown in the map card when there is no active map and the robot is not
/// currently mapping. Gives the user two clear next steps: activate a saved
/// map or create a new one — instead of a blank dark box with no guidance.
class _NoActiveMapPrompt extends StatelessWidget {
  const _NoActiveMapPrompt({required this.robotIp});
  final String robotIp;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.map_outlined,
              size: 36,
              color: AppColors.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'No active map',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Activate a saved map or create a new one to start navigating.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MapsListScreen()),
                  ),
                  icon: const Icon(Icons.layers_rounded, size: 16),
                  label: const Text('My Maps'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const CreateMapScreen()),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Create Map'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}



/// Low-battery banner matching reference §"Low Battery" — a real threshold
/// on real telemetry (not the fabricated 15% from the mockup's own text;
/// coincidentally the same number, chosen independently as a sane cutoff).
class _LowBatteryBanner extends StatelessWidget {
  const _LowBatteryBanner({required this.percentage});

  final double percentage;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.warningGradient,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            const Icon(Icons.battery_alert_rounded, color: AppColors.danger),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Low Battery',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  Text('${percentage.round()}% remaining — dock soon',
                      style: const TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            ),
            TextButton(
              onPressed: () =>
                  pushWithTelemetry(context, const DockChargeScreen()),
              child: const Text('Go to Dock'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live for as long as the Dashboard is on screen — connects to the SDK's
/// events stream the same way AlertsLogScreen does (see SdkEventsService),
/// showing the most recent non-info event as a preview, tapping through to
/// the full log. Honest empty state when nothing has come through yet. The
/// pulse dot mirrors the socket's own live/reconnecting state, not a fixed
/// decoration.
class _AlertsCard extends StatefulWidget {
  const _AlertsCard({required this.robotIp});

  final String robotIp;

  @override
  State<_AlertsCard> createState() => _AlertsCardState();
}

class _AlertsCardState extends State<_AlertsCard> {
  @override
  void initState() {
    super.initState();
    AlertsController.instance.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AlertsController.instance.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AlertsController.instance.ensureStarted(widget.robotIp);
    final connected = AlertsController.instance.isConnected;
    final alerts = AlertsController.instance.events
        .where((e) => e.severity != SdkEventSeverity.info)
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('Alerts & Notifications',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(width: AppSpacing.sm),
                StatusPulseDot(
                  color:
                      connected ? AppColors.success : AppColors.textTertiary,
                  live: connected,
                  size: 6,
                ),
                if (alerts.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${alerts.length}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.danger),
                    ),
                  ),
                ],
                const Spacer(),
                if (alerts.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                    tooltip: 'Clear all alerts',
                    onPressed: () {
                      AlertsController.instance.clear();
                      setState(() {});
                    },
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            if (alerts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline_rounded,
                        size: 20, color: AppColors.success),
                    SizedBox(width: AppSpacing.sm),
                    Text('No active alerts',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ],
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: alerts.length,
                  separatorBuilder: (_, __) => const Divider(height: 10),
                  itemBuilder: (context, idx) {
                    final alert = alerts[idx];
                    final isCritical = alert.severity == SdkEventSeverity.critical;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          isCritical
                              ? Icons.error_rounded
                              : Icons.warning_amber_rounded,
                          size: 18,
                          color: isCritical
                              ? AppColors.danger
                              : AppColors.warning,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                alert.name.replaceAll('.', ' · '),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              if (alert.message.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  alert.message,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTimeAgo(alert.receivedAt),
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _AppBarBatteryWidget extends StatelessWidget {
  const _AppBarBatteryWidget({
    required this.telemetry,
  });

  final RobotTelemetryProvider telemetry;

  @override
  Widget build(BuildContext context) {
    final pct = telemetry.batteryPercentage;
    final isCharging = telemetry.chargeStatus == ChargeStatus.charging;
    final isLow = pct != null && pct < 20;

    final Color statusColor = isCharging
        ? AppColors.accent
        : isLow
            ? AppColors.danger
            : (pct != null && pct < 45)
                ? AppColors.warning
                : AppColors.success;

    final voltage = (telemetry.batteryDetail?['voltage'] as num?)?.toDouble();
    final String tooltip = [
      if (pct != null) 'Battery: ${pct.toStringAsFixed(0)}%',
      if (isCharging) 'Status: Charging ⚡' else 'Status: Discharging',
      if (voltage != null) 'Voltage: ${voltage.toStringAsFixed(2)} V',
      if (telemetry.batteryTemperature != null)
        'Temperature: ${telemetry.batteryTemperature!.toStringAsFixed(0)}°C',
    ].join('\n');

    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DockChargeScreen()),
        ),
        child: Container(
          margin: const EdgeInsets.only(right: AppSpacing.md),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: statusColor.withValues(alpha: isCharging || isLow ? 0.6 : 0.28),
              width: isCharging || isLow ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MiniBatteryGauge(
                percent: pct ?? 0,
                isCharging: isCharging,
                color: statusColor,
              ),
              const SizedBox(width: 7),
              Text(
                telemetry.formatBatteryPercent(),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (isCharging) ...[
                const SizedBox(width: 3),
                Icon(Icons.bolt_rounded, size: 14, color: statusColor),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniBatteryGauge extends StatelessWidget {
  const _MiniBatteryGauge({
    required this.percent,
    required this.isCharging,
    required this.color,
  });

  final double percent;
  final bool isCharging;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fillFraction = (percent / 100.0).clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 11,
          padding: const EdgeInsets.all(1.2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2.5),
            border: Border.all(color: color, width: 1.2),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: (20 - 2.4 - 2.4) * fillFraction,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1.2),
                color: color,
              ),
            ),
          ),
        ),
        Container(
          width: 1.5,
          height: 4.5,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(1),
              bottomRight: Radius.circular(1),
            ),
          ),
        ),
      ],
    );
  }
}
