import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ros2_api/ros2_api.dart';

import '../providers/connection_provider.dart';
import '../providers/robot_status.dart';
import '../providers/robot_telemetry_provider.dart';
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
import '../services/road_network_controller.dart';
import '../widgets/design/animated_metric.dart';

import '../widgets/design/fade_in.dart';
import '../widgets/design/status_pulse.dart';
import '../utils/push_with_telemetry.dart';
import '../widgets/map/not_localized_banner.dart';
import '../widgets/map/occupancy_grid_view.dart';
import '../widgets/sdk_state_builder.dart';
import 'alerts/alerts_log_screen.dart';
import 'dock/dock_charge_screen.dart';
import 'maps/map_view_screen.dart';
import 'maps/maps_list_screen.dart';
import 'maps/create_map_screen.dart';
import 'media/robot_media_screen.dart';
import 'voice/voice_assistant_screen.dart';
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
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inter = _activeRobotInteraction;
    final p = inter?['params'] as Map<String, dynamic>? ?? {};
    final title = inter?['title']?.toString() ?? p['title']?.toString() ?? 'Web Browser';
    final subtype = (inter?['subtype'] ?? p['subtype'] ?? 'browser').toString().toLowerCase();
    final isBrowser = subtype == 'browser';

    final accentColor = isBrowser ? const Color(0xFF0D9488) : colors.primary;
    final bgColor = isBrowser
        ? (isDark ? const Color(0xFF134E4A).withValues(alpha: 0.25) : const Color(0xFFF0FDFA))
        : (isDark ? colors.primary.withValues(alpha: 0.12) : const Color(0xFFFFF3EE));
    final borderColor = isBrowser
        ? (isDark ? const Color(0xFF0D9488).withValues(alpha: 0.5) : const Color(0xFF99F6E4))
        : (isDark ? colors.primary.withValues(alpha: 0.5) : const Color(0xFFFFD4C2));
    final titleColor = isBrowser
        ? (isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E))
        : colors.textPrimary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(
          color: borderColor,
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isBrowser ? Icons.language_rounded : Icons.tablet_mac_rounded,
              color: accentColor,
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
                        color: titleColor,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'ROBOT SCREEN',
                        style: TextStyle(
                          color: accentColor,
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
                  style: TextStyle(color: colors.textSecondary, fontSize: 11.5),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.perm_media_outlined),
            tooltip: 'Robot Media & Signage (DND)',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const RobotMediaScreen(),
              ));
            },
          ),
          IconButton(
            icon: const Icon(Icons.mic_none_rounded),
            tooltip: 'Live Voice Assistant',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => VoiceAssistantScreen(robotIp: widget.robot.ip),
              ));
            },
          ),
          _AppBarBatteryWidget(telemetry: telemetry),
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
                    child: _StatRow(
                        telemetry: telemetry, sdkState: sdkState),
                  ),
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
    final colors = AppColors.of(context);
    final battery = telemetry.batteryPercentage;
    final status = deriveRobotStatus(telemetry: telemetry, sdkState: sdkState);
    final charging = telemetry.chargeStatus == ChargeStatus.charging ||
        telemetry.chargeStatus == ChargeStatus.full;
    final isActive = _isActiveStatus(status);

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
                              Icon(status.icon, size: 14, color: statusColor),
                              const SizedBox(width: 4),
                              AnimatedSwitcher(
                                duration: AppMotion.fast,
                                child: Text(
                                  'Online · $statusLabel',
                                  key: ValueKey('${status}_$isStopping'),
                                  style: TextStyle(
                                      color: colors.textSecondary),
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
                              style: TextStyle(
                                  color: colors.textTertiary, fontSize: 13),
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
                  color: charging ? AppColors.success : colors.textSecondary,
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
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              color: charging ? AppColors.success : colors.primary,
            ),
          ],
        ),
      ),
    );
      },
    );
  }
}

String _formatMissionProgressText(SdkState sdkState) {
  final status = sdkState.missionStatus?.toLowerCase();
  if (status == null || status == 'idle' || status == '') return 'IDLE';
  if (status == 'paused' && sdkState.pauseReason == 'low_battery') {
    return 'PAUSED (CHARGING)';
  }

  final parts = <String>[status.toUpperCase()];
  if (sdkState.stepIndex != null && sdkState.stepIndex! >= 0) {
    final stepNum = sdkState.stepIndex! + 1;
    final total = sdkState.stepTotal;
    parts.add(total != null && total > 0 ? 'Step $stepNum/$total' : 'Step $stepNum');
  }
  if (sdkState.loopIndex != null) {
    final loopNum = sdkState.loopIndex! + 1;
    final lTotal = sdkState.loopTotal;
    if (lTotal != null && lTotal > 1) {
      parts.add('Lap $loopNum/$lTotal');
    } else if (lTotal == null) {
      parts.add('Lap $loopNum (∞)');
    }
  }
  return parts.join(' · ');
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
              child: Tooltip(
                message: sdkState.activeNodeLabel ??
                    sdkState.missionMessage ??
                    sdkState.missionName ??
                    '',
                child: Text(
                  _formatMissionProgressText(sdkState),
                  key: ValueKey(
                      '${sdkState.missionStatus}_${sdkState.stepIndex}_${sdkState.loopIndex}'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: sdkState.missionStatus == 'paused' &&
                                sdkState.pauseReason == 'low_battery'
                            ? AppColors.warning
                            : (sdkState.missionStatus == 'failed'
                                ? AppColors.danger
                                : null),
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
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
  final sheetColors = AppColors.of(context);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: sheetColors.surface,
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
                    color: sheetColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Icon(Icons.my_location_rounded,
                      color: sheetColors.primary, size: 20),
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
              Text(
                'Seed or reset AMCL belief of the robot position:',
                style: TextStyle(fontSize: 12, color: sheetColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: sheetColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.ev_station_rounded,
                      color: sheetColors.accent, size: 22),
                ),
                title: const Text('Robot at Dock',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    'Seed AMCL pose from known docking station coordinates',
                    style: TextStyle(fontSize: 12, color: sheetColors.textSecondary)),
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
                    color: sheetColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.pin_drop_rounded,
                      color: sheetColors.primary, size: 22),
                ),
                title: const Text('Set 2D Pose on Map',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    'Tap & drag robot heading directly on the interactive map',
                    style: TextStyle(fontSize: 12, color: sheetColors.textSecondary)),
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
                    color: sheetColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.sync_rounded,
                      color: sheetColors.accent, size: 22),
                ),
                title: const Text('Auto-Relocalize (360° Spin)',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    'Autonomous in-place rotation to disperse and converge particles',
                    style: TextStyle(fontSize: 12, color: sheetColors.textSecondary)),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final messenger = ScaffoldMessenger.of(context);
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text('Searching position: Performing autonomous relocalization scan…'),
                          ),
                        ],
                      ),
                      duration: Duration(seconds: 50),
                    ),
                  );
                  try {
                    final res = await api.recoverRelocalization(maxTries: 3, timeoutSec: 50.0);
                    messenger.hideCurrentSnackBar();
                    final converged = res['converged'] == true;
                    final elapsed = res['elapsed_sec'] ?? '';
                    final tries = res['tries'] ?? 1;
                    messenger.showSnackBar(SnackBar(
                      content: Text(converged
                          ? 'Relocalized successfully in ${elapsed}s ($tries scan cycle${tries == 1 ? "" : "s"})! AMCL converged.'
                          : 'Relocalization timed out after $tries scans. Check robot surroundings.'),
                      backgroundColor: converged ? AppColors.success : AppColors.warning,
                      duration: const Duration(seconds: 6),
                    ));
                  } catch (e) {
                    messenger.hideCurrentSnackBar();
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
                    color: sheetColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.radar_rounded,
                      color: sheetColors.warning, size: 22),
                ),
                title: const Text('Global Search & Auto-Scan',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    'Disperse particles across entire map and rotate automatically to identify position',
                    style: TextStyle(fontSize: 12, color: sheetColors.textSecondary)),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final messenger = ScaffoldMessenger.of(context);
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                                'Searching position: Dispersing AMCL & performing autonomous scan…'),
                          ),
                        ],
                      ),
                      duration: Duration(seconds: 50),
                    ),
                  );
                  try {
                    final res = await api.reinitializeGlobalLocalization(spin: true, maxTries: 3, timeoutSec: 50.0);
                    messenger.hideCurrentSnackBar();
                    final converged = res['converged'] == true;
                    final elapsed = res['elapsed_sec'] ?? '';
                    final tries = res['tries'] ?? 1;
                    messenger.showSnackBar(SnackBar(
                      content: Text(converged
                          ? 'Position identified! Relocalized in ${elapsed}s ($tries scan cycle${tries == 1 ? "" : "s"}). AMCL converged.'
                          : 'Relocalization timed out after $tries scans. Check robot surroundings.'),
                      backgroundColor: converged ? AppColors.success : AppColors.warning,
                      duration: const Duration(seconds: 6),
                    ));
                  } catch (e) {
                    messenger.hideCurrentSnackBar();
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
    final colors = AppColors.of(context);
    final body = Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 18, color: colors.primary),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          value,
          Text(label,
              style: TextStyle(
                  color: colors.textSecondary, fontSize: 12)),
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
    final colors = AppColors.of(context);
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
                value: Tooltip(
                  message: sdkState.activeNodeLabel ??
                      sdkState.missionMessage ??
                      sdkState.missionName ??
                      '',
                  child: Text(
                    _formatMissionProgressText(sdkState),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: sdkState.missionStatus == 'paused' &&
                                  sdkState.pauseReason == 'low_battery'
                              ? AppColors.warning
                              : (sdkState.missionStatus == 'failed'
                                  ? AppColors.danger
                                  : null),
                        ),
                    overflow: TextOverflow.ellipsis,
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
                icon: Icons.my_location_rounded,
                label: 'AMCL Localization',
                trailing: Icon(Icons.touch_app_rounded,
                    size: 14, color: colors.textTertiary),
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
                                  : colors.textTertiary)
                              : (telemetry.localizationHealth == 'degraded'
                                  ? AppColors.warning
                                  : AppColors.success),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded,
                        size: 11, color: colors.textTertiary),
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

  @override
  void initState() {
    super.initState();
    DockPoseController.instance.addListener(_onDockPoseChanged);
    RoadNetworkController.instance.addListener(_onDockPoseChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDockPose();
      DockPoseController.instance.refresh(SdkApiService(widget.robotIp));
      ZonesController.instance
          .refresh(SdkApiService(widget.robotIp), map: widget.mapName);
      RoadNetworkController.instance
          .refresh(SdkApiService(widget.robotIp), map: widget.mapName);
    });
  }

  void _onDockPoseChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    DockPoseController.instance.removeListener(_onDockPoseChanged);
    RoadNetworkController.instance.removeListener(_onDockPoseChanged);
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
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                    color: AppColors.of(context).surfaceSunken,
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
                                  Text(
                                    'Shutting down SLAM on robot. This takes a few seconds.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.of(context).textSecondary),
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
                                    interactive: widget.interactive,
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
                                    roadNetwork: visibleLayers.contains(MapLayer.roadNetwork)
                                        ? RoadNetworkController.instance.value
                                        : null,
                                    showRoadNetwork:
                                        visibleLayers.contains(MapLayer.roadNetwork),
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
    final colors = AppColors.of(context);
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
              color: colors.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'No active map',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Activate a saved map or create a new one to start navigating.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
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
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: colors.warningGradient,
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
                      style: TextStyle(color: colors.textSecondary)),
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
    // Shared with AlertsLogScreen (see AlertsController's own doc) — the
    // first of the two to build starts it, both read the same history.
    AlertsController.instance.ensureStarted(widget.robotIp);
    final connected = AlertsController.instance.isConnected;
    final colors = AppColors.of(context);
    final alerts = AlertsController.instance.events
        .where((e) => e.severity != SdkEventSeverity.info)
        .toList();
    return Card(
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const AlertsLogScreen())),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Alerts',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(width: AppSpacing.sm),
                  StatusPulseDot(
                    color:
                        connected ? AppColors.success : colors.textTertiary,
                    live: connected,
                    size: 6,
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: colors.textSecondary),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              AnimatedSwitcher(
                duration: AppMotion.medium,
                switchInCurve: AppMotion.enter,
                child: alerts.isEmpty
                    ? Row(
                        key: const ValueKey('empty'),
                        children: [
                          const Icon(Icons.check_circle_outline_rounded,
                              size: 20, color: AppColors.success),
                          const SizedBox(width: AppSpacing.sm),
                          Text('No active alerts',
                              style: TextStyle(color: colors.textSecondary)),
                        ],
                      )
                    : Row(
                        key: ValueKey(alerts.first.receivedAt),
                        children: [
                          Icon(
                            alerts.first.severity == SdkEventSeverity.critical
                                ? Icons.error_rounded
                                : Icons.warning_amber_rounded,
                            size: 20,
                            color: alerts.first.severity ==
                                    SdkEventSeverity.critical
                                ? AppColors.danger
                                : AppColors.warning,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                              child: Text(
                                  alerts.first.name.replaceAll('.', ' · '))),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
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
