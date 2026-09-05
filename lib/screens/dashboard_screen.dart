import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ros2_api/ros2_api.dart';

import '../providers/connection_provider.dart';
import '../providers/robot_status.dart';
import '../providers/robot_telemetry_provider.dart';
import '../services/alerts_controller.dart';
import '../services/map_layers_controller.dart';
import '../services/robot_connection_store.dart';
import '../services/sdk_api_service.dart';
import '../services/sdk_events_service.dart';
import '../services/sdk_state_service.dart' show SdkState;
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../theme/breakpoints.dart';
import '../utils/localize_at_dock.dart';
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
    return _DashboardContent(connection: connection);
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({required this.connection});

  final ConnectionProvider connection;

  @override
  Widget build(BuildContext context) {
    final telemetry = context.watch<RobotTelemetryProvider>();
    final robot = connection.robot!;
    final isDesktop = Breakpoints.of(context) == DeviceClass.desktop;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          if (isDesktop) ...[
            if (telemetry.localized)
              Container(
                margin: const EdgeInsets.only(right: AppSpacing.sm),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.gps_fixed_rounded, size: 14, color: AppColors.success),
                    const SizedBox(width: 6),
                    Text(
                      'AMCL: (${telemetry.poseX?.toStringAsFixed(2) ?? '--'}, ${telemetry.poseY?.toStringAsFixed(2) ?? '--'})',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success),
                    ),
                  ],
                ),
              )
            else
              Container(
                margin: const EdgeInsets.only(right: AppSpacing.sm),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.warning),
                    SizedBox(width: 6),
                    Text(
                      'Not Localized',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.warning),
                    ),
                  ],
                ),
              ),
            if (telemetry.dockStatus != null)
              Container(
                margin: const EdgeInsets.only(right: AppSpacing.sm),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.dock_rounded, size: 14, color: AppColors.accent),
                    const SizedBox(width: 6),
                    Text(
                      'Dock: ${telemetry.dockStatus}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent),
                    ),
                  ],
                ),
              ),
            Container(
              margin: const EdgeInsets.only(right: AppSpacing.md),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    telemetry.chargeStatus == ChargeStatus.charging
                        ? Icons.bolt_rounded
                        : Icons.battery_full_rounded,
                    size: 14,
                    color: telemetry.batteryPercentage != null && telemetry.batteryPercentage! < 20
                        ? AppColors.danger
                        : AppColors.success,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${telemetry.batteryPercentage?.round() ?? '--'}%',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: isDesktop
            ? SdkStateBuilder(
                robotIp: robot.ip,
                builder: (context, sdkState) {
                  final battery = telemetry.batteryPercentage;
                  final charging =
                      telemetry.chargeStatus == ChargeStatus.charging ||
                          telemetry.chargeStatus == ChargeStatus.full;

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
                              if (battery != null &&
                                  battery <= 15 &&
                                  !charging) ...[
                                _LowBatteryBanner(percentage: battery),
                                const SizedBox(height: AppSpacing.lg),
                              ],
                              _RobotCard(
                                  robot: robot,
                                  telemetry: telemetry,
                                  sdkState: sdkState),
                              const SizedBox(height: AppSpacing.lg),
                              _MapPreviewCard(
                                ros2: connection.ros2!,
                                mapName: sdkState.mapName,
                                robotIp: robot.ip,
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
                              _AlertsCard(robotIp: robot.ip),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              )
            : CenteredFormColumn(
                maxWidth: 720,
                child: SdkStateBuilder(
                  robotIp: robot.ip,
                  builder: (context, sdkState) {
                    final battery = telemetry.batteryPercentage;
                    final charging =
                        telemetry.chargeStatus == ChargeStatus.charging ||
                            telemetry.chargeStatus == ChargeStatus.full;
                    var step = 0;
                    Duration nextDelay() =>
                        Duration(milliseconds: 60 * step++);

                    return ListView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      children: [
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
                              robot: robot,
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
                              ros2: connection.ros2!,
                              mapName: sdkState.mapName,
                              robotIp: robot.ip),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        FadeSlideIn(
                          delay: nextDelay(),
                          child: _AlertsCard(robotIp: robot.ip),
                        ),
                      ],
                    );
                  },
                ),
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
                              color: status.color, live: isActive, size: 8),
                          const SizedBox(width: 6),
                          AnimatedSwitcher(
                            duration: AppMotion.fast,
                            child: Text(
                              'Online · ${status.label}',
                              key: ValueKey(status),
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
                          _subtitleFor(status),
                          key: ValueKey('subtitle-$status'),
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
                  formatter: (v) => '${v.round()}%',
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

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(height: AppSpacing.xs),
            value,
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _StatGridDesktop extends StatelessWidget {
  const _StatGridDesktop({required this.telemetry, required this.sdkState});

  final RobotTelemetryProvider telemetry;
  final SdkState sdkState;

  @override
  Widget build(BuildContext context) {
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
                value: Text(
                  telemetry.localized ? 'LOCALIZED' : 'UNLOCALIZED',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: telemetry.localized
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                  overflow: TextOverflow.ellipsis,
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
    this.height = 140,
    this.interactive = false,
  });

  final Ros2 ros2;
  final String? mapName;
  final String robotIp;
  final double height;
  final bool interactive;

  @override
  State<_MapPreviewCard> createState() => _MapPreviewCardState();
}

class _MapPreviewCardState extends State<_MapPreviewCard> {
  ({double x, double y, double theta})? _dockPose;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDockPose());
  }

  /// Same fallback Map View's own live view uses — see the doc on
  /// [OccupancyGridView.dockPoseOverride] for why the live `/dock_pose`
  /// topic alone isn't reliable enough to draw the dock pin from.
  Future<void> _loadDockPose() async {
    final dock = await fetchDockPose(SdkApiService(widget.robotIp));
    if (!mounted || dock == null) return;
    setState(() => _dockPose = dock);
  }

  @override
  Widget build(BuildContext context) {
    final telemetry = context.watch<RobotTelemetryProvider>();
    final api = SdkApiService(widget.robotIp);
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
                    widget.mapName != null
                        ? 'LiveMap-${widget.mapName}'
                        : 'Live Map',
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MapViewScreen()),
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
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ValueListenableBuilder<Set<MapLayer>>(
                        valueListenable: MapLayersController.instance,
                        builder: (context, visibleLayers, _) =>
                            OccupancyGridView(
                          ros2: widget.ros2,
                          interactive: widget.interactive,
                          showDock: visibleLayers.contains(MapLayer.dock),
                          showPath: visibleLayers.contains(MapLayer.path),
                          showLaserScan:
                              visibleLayers.contains(MapLayer.laserScan),
                          initialPose: telemetry.rawPose,
                          initialPath: telemetry.currentPath,
                          showGlobalCostmap:
                              visibleLayers.contains(MapLayer.globalCostmap),
                          showLocalCostmap:
                              visibleLayers.contains(MapLayer.localCostmap),
                          dockPoseOverride: _dockPose,
                          showLocalizationBadge: false,
                        ),
                      ),
                    ),
                    if (!telemetry.localized)
                      Positioned(
                        left: AppSpacing.xs,
                        right: AppSpacing.xs,
                        top: AppSpacing.xs,
                        child: NotLocalizedBanner(
                          api: api,
                          onDecline: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text(
                                    'Open Map to set the initial pose.'),
                                action: SnackBarAction(
                                  label: 'Open Map',
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const MapViewScreen(
                                          initialPosePicking: true),
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
    // Shared with AlertsLogScreen (see AlertsController's own doc) — the
    // first of the two to build starts it, both read the same history.
    AlertsController.instance.ensureStarted(widget.robotIp);
    final connected = AlertsController.instance.isConnected;
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
                        connected ? AppColors.success : AppColors.textTertiary,
                    live: connected,
                    size: 6,
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppColors.textSecondary),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              AnimatedSwitcher(
                duration: AppMotion.medium,
                switchInCurve: AppMotion.enter,
                child: alerts.isEmpty
                    ? const Row(
                        key: ValueKey('empty'),
                        children: [
                          Icon(Icons.check_circle_outline_rounded,
                              size: 20, color: AppColors.success),
                          SizedBox(width: AppSpacing.sm),
                          Text('No active alerts',
                              style: TextStyle(color: AppColors.textSecondary)),
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
