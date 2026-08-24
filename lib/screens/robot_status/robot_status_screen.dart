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

/// Robot Status screen — the detailed diagnostic counterpart to
/// `DashboardScreen`'s at-a-glance summary. Same data sources
/// (`LiveTelemetryProvider`, `DockingService`, `MissionExecutionService`,
/// `LaunchManager`), presented with more detail: connection state, per-
/// launch identifiers, dock/mission detail rows, and the current teleop
/// command when one is active (a piece of real data
/// `LiveTelemetryProvider` already exposes — `commandedLinear`/
/// `commandedAngular` — that Dashboard's compact tiles don't have room
/// for).
///
/// Same scope caveats as Dashboard: no pose/measured-velocity (not in a
/// shared provider yet) and no fault/E-STOP (no signal exists anywhere in
/// the app).
class RobotStatusScreen extends StatelessWidget {
  const RobotStatusScreen({super.key});

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
                  Text('Robot Status', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: AppSpacing.lg),
                  _IdentityCard(
                    connection: connection,
                    telemetry: telemetry,
                    launchManager: launchManager,
                    missionExecution: missionExecution,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Battery & system', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  StatTileGrid(
                    columns: sizeClass.isExpandedOrWider ? 3 : 2,
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
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Active launches', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  _LaunchesCard(launchManager: launchManager),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Docking', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  const _DockingDetailCard(),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Mission', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  _MissionDetailCard(missionExecution: missionExecution),
                  if (telemetry.teleopActive) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text('Teleop command', style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    _TeleopCommandCard(telemetry: telemetry),
                  ],
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  final ConnectionProvider connection;
  final LiveTelemetryProvider telemetry;
  final LaunchManager launchManager;
  final MissionExecutionService missionExecution;

  const _IdentityCard({
    required this.connection,
    required this.telemetry,
    required this.launchManager,
    required this.missionExecution,
  });

  String _connectionStateLabel(bool isConnected) =>
      isConnected ? 'Connected' : 'Disconnected';

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
          // provider yet.
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(name, style: theme.textTheme.titleLarge),
                    ),
                    StatusPill(
                      label: robotStateLabel(state),
                      color: robotStateColor(state, statusColors),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _InfoRow(
                    label: 'IP address',
                    value: connection.ip.isNotEmpty ? connection.ip : '—'),
                _InfoRow(
                  label: 'Connection',
                  value: _connectionStateLabel(connection.isConnected),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _LaunchesCard extends StatelessWidget {
  final LaunchManager launchManager;

  const _LaunchesCard({required this.launchManager});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final launches = launchManager.activeLaunches;
    if (launches.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading:
              Icon(Icons.power_settings_new, color: theme.colorScheme.outline),
          title: const Text('No active launches'),
        ),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: launches.entries
            .map((entry) => ListTile(
                  leading:
                      Icon(Icons.play_circle, color: theme.colorScheme.primary),
                  title: Text(entry.value),
                  subtitle: Text(entry.key,
                      style: const TextStyle(fontFamily: 'monospace')),
                ))
            .toList(),
      ),
    );
  }
}

class _DockingDetailCard extends StatelessWidget {
  const _DockingDetailCard();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: DockingService.instance,
      builder: (context, _) {
        final docking = DockingService.instance;
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(label: 'Status', value: docking.status),
                _InfoRow(
                    label: 'Docked', value: docking.isDocked ? 'Yes' : 'No'),
                _InfoRow(label: 'Busy', value: docking.isBusy ? 'Yes' : 'No'),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MissionDetailCard extends StatelessWidget {
  final MissionExecutionService missionExecution;

  const _MissionDetailCard({required this.missionExecution});

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
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow(label: 'Mission', value: mission.missionName),
            _InfoRow(
              label: 'Progress',
              value:
                  'Item ${missionExecution.currentIndex + 1} of ${mission.items.length}',
            ),
            _InfoRow(
                label: 'Paused',
                value: missionExecution.isPaused ? 'Yes' : 'No'),
          ],
        ),
      ),
    );
  }
}

class _TeleopCommandCard extends StatelessWidget {
  final LiveTelemetryProvider telemetry;

  const _TeleopCommandCard({required this.telemetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow(
              label: 'Linear',
              value:
                  '${telemetry.commandedLinear?.toStringAsFixed(2) ?? '—'} m/s',
            ),
            _InfoRow(
              label: 'Angular',
              value:
                  '${telemetry.commandedAngular?.toStringAsFixed(2) ?? '—'} rad/s',
            ),
          ],
        ),
      ),
    );
  }
}
