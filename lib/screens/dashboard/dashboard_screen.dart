import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/connection_provider.dart';
import '../../providers/live_telemetry_provider.dart';
import '../../providers/robot_state.dart';
import '../../services/docking_service.dart';
import '../../services/launch_service.dart';
import '../../services/mission_execution_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_breakpoints.dart';
import '../../widgets/status/status_tiles.dart';

/// Landing/overview screen — the redesign's new "Dashboard & Home" section.
/// No existing analog before this: `home_screen.dart` stays the mode-router
/// shell, this is a real peer destination in the nav rail showing the
/// robot's current state at a glance.
///
/// Deliberately built only from data already exposed by a *shared*
/// provider/service — no new ROS subscriptions. Two things the reference
/// design shows that this screen does NOT (yet) — flagged rather than
/// faked:
///  - **Live map preview / speed / pose** — position and measured velocity
///    currently live inside `NavigationOdometryController`, owned by
///    `navigation_screen.dart`, not a shared provider. Showing them here
///    would mean a duplicate ROS subscription (exactly what
///    `LiveTelemetryProvider` exists to avoid) — left out until pose/
///    velocity are centralized the same way battery/temperature were.
///  - **Alerts feed** — depends on the Alerts & Log screen's event log,
///    not yet built.
///
/// Shares its stat-tile primitives (`StatTile`/`StatTileGrid`/`StatusPill`)
/// and the `RobotState` color/label mapping with `RobotStatusScreen` —
/// this is the at-a-glance summary, that's the detailed diagnostic view.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.lightTheme,
      child: Builder(builder: (context) {
        final theme = Theme.of(context);
        final sizeClass = WindowSizeClass.of(context);

        final connection = context.watch<ConnectionProvider>();
        final telemetry = context.watch<LiveTelemetryProvider>();
        final launchManager = context.watch<LaunchManager>();
        final missionExecution = context.watch<MissionExecutionService>();

        return Container(
          color: AppColors.lightBackground,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RobotHeaderCard(
                    connection: connection,
                    telemetry: telemetry,
                    launchManager: launchManager,
                    missionExecution: missionExecution,
                  ),
                  _StatusBanners(
                    telemetry: telemetry,
                    missionExecution: missionExecution,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  StatTileGrid(
                    columns: sizeClass.isExpandedOrWider ? 4 : 2,
                    tiles: [
                      BatteryTile(percent: telemetry.batteryPercent),
                      TemperatureTile(
                        label: 'Battery temp',
                        celsius: telemetry.batteryTempC,
                      ),
                      TemperatureTile(
                        label: 'CPU temp',
                        celsius: telemetry.cpuTempC,
                      ),
                      _SessionTile(session: launchManager.activeSession),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Docking', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  const _DockingCard(),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Mission', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  _MissionCard(missionExecution: missionExecution),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _RobotHeaderCard extends StatelessWidget {
  final ConnectionProvider connection;
  final LiveTelemetryProvider telemetry;
  final LaunchManager launchManager;
  final MissionExecutionService missionExecution;

  const _RobotHeaderCard({
    required this.connection,
    required this.telemetry,
    required this.launchManager,
    required this.missionExecution,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: DockingService.instance,
      builder: (context, _) {
        final state = deriveRobotState(
          connection: connection,
          launchManager: launchManager,
          missionExecution: missionExecution,
          docking: DockingService.instance,
          // See DashboardScreen's doc comment — pose isn't in a shared
          // provider yet, so this never reports "localizing" from here
          // specifically.
          poseReceived: true,
          teleopActive: telemetry.teleopActive,
        );
        final statusColors =
            theme.extension<AppStatusColors>() ?? AppStatusColors.standard;
        final name = connection.activeRobot?.name ??
            (connection.ip.isNotEmpty ? connection.ip : 'Robot');

        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.smart_toy_outlined,
                    color: theme.colorScheme.onPrimaryContainer,
                    size: 26,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 2),
                      Text(
                        connection.ip.isNotEmpty ? connection.ip : 'No IP',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                StatusPill(
                  label: robotStateLabel(state),
                  color: robotStateColor(state, statusColors),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Low-battery / mission-failed banners — the redesign reference's "small
/// state screens" (Low Battery, Mission Failed), built as inline banners on
/// Dashboard per the plan rather than separate full screens, since both are
/// transient conditions layered over whatever else is going on. Connection
/// Lost isn't duplicated here — losing connection already swaps the whole
/// shell to `ConnectionScreen` (see `home_screen.dart`), so a banner for it
/// here would never actually be visible. Obstacle Detected / E-STOP Active
/// aren't here because no signal for either exists yet (see
/// `AlertLogService`'s doc comment).
class _StatusBanners extends StatelessWidget {
  static const double _lowBatteryThreshold = 20;

  final LiveTelemetryProvider telemetry;
  final MissionExecutionService missionExecution;

  const _StatusBanners({
    required this.telemetry,
    required this.missionExecution,
  });

  @override
  Widget build(BuildContext context) {
    final banners = <Widget>[];
    final battery = telemetry.batteryPercent;
    if (battery != null && battery <= _lowBatteryThreshold) {
      banners.add(_Banner(
        icon: Icons.battery_alert,
        color: Colors.red,
        text: 'Low battery — ${battery.round()}% remaining',
      ));
    }
    if (!missionExecution.isRunning && missionExecution.errorMessage != null) {
      banners.add(_Banner(
        icon: Icons.error_outline,
        color: Colors.red,
        text: 'Mission failed: ${missionExecution.errorMessage}',
        onDismiss: missionExecution.clearError,
      ));
    }
    if (banners.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        const SizedBox(height: AppSpacing.sm),
        ...banners,
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback? onDismiss;

  const _Banner({
    required this.icon,
    required this.color,
    required this.text,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: color,
              onPressed: onDismiss,
              tooltip: 'Dismiss',
            ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final SessionType session;

  const _SessionTile({required this.session});

  @override
  Widget build(BuildContext context) {
    final label = switch (session) {
      SessionType.none => 'None',
      SessionType.mapping => 'Mapping',
      SessionType.navigation => 'Navigation',
    };
    return StatTile(
      label: 'Active session',
      value: label,
      icon: Icons.play_circle_outline,
    );
  }
}

class _DockingCard extends StatelessWidget {
  const _DockingCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: DockingService.instance,
      builder: (context, _) {
        final docking = DockingService.instance;
        final color = docking.isFault
            ? theme.colorScheme.error
            : (docking.isDocked
                ? Colors.green
                : (docking.isBusy
                    ? Colors.lightBlue
                    : theme.colorScheme.outline));
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: Icon(
              docking.isFault ? Icons.error_outline : Icons.ev_station,
              color: color,
            ),
            title: Text(docking.statusLabel),
          ),
        );
      },
    );
  }
}

class _MissionCard extends StatelessWidget {
  final MissionExecutionService missionExecution;

  const _MissionCard({required this.missionExecution});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!missionExecution.isRunning ||
        missionExecution.currentMission == null) {
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(Icons.check_circle_outline,
              color: theme.colorScheme.outline),
          title: const Text('No mission running'),
        ),
      );
    }
    final mission = missionExecution.currentMission!;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.play_arrow, color: theme.colorScheme.primary),
        title: Text(mission.missionName),
        subtitle: Text(
            'Item ${missionExecution.currentIndex + 1} of ${mission.items.length}'),
      ),
    );
  }
}
