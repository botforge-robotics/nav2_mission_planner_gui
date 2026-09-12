import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../providers/robot_status.dart';
import '../../providers/robot_telemetry_provider.dart';
import '../../services/locations_controller.dart';
import '../../services/sdk_api_service.dart';
import '../../services/sdk_state_service.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/design/animated_metric.dart';
import '../../widgets/design/fade_in.dart';
import '../../widgets/design/skeleton.dart';
import '../../widgets/design/status_pulse.dart';
import '../splash_screen.dart';

/// Reference §10 (Robot Status). Identity/uptime come from the SDK's
/// GET /system/info (an SDK-exclusive read — rosapi has no equivalent
/// "how long has this process been up" concept); battery/speed/localization
/// stay on the app's core telemetry path. "Current Location" is derived
/// client-side as the nearest saved waypoint within 1m of the robot's pose —
/// an honest approximation labelled as such, not a real semantic field the
/// backend tracks.
class RobotStatusScreen extends StatefulWidget {
  const RobotStatusScreen({super.key});

  @override
  State<RobotStatusScreen> createState() => _RobotStatusScreenState();
}

class _RobotStatusScreenState extends State<RobotStatusScreen> {
  Map<String, dynamic>? _info;
  SdkApiException? _infoError;
  List<Map<String, dynamic>>? _locations;
  Map<String, dynamic>? _health;
  bool _showAdvanced = false;

  SdkApiService? _api;

  Future<void> _load() async {
    final api = _api;
    if (api == null) return;
    try {
      final info = await api.systemInfo();
      if (mounted) setState(() => _info = info);
    } on SdkApiException catch (e) {
      if (mounted) setState(() => _infoError = e);
    }
    try {
      final locations = await api.listWaypoints();
      if (mounted) setState(() => _locations = locations);
    } on SdkApiException {
      // Optional enrichment for "current location" only — silent.
    }
  }

  Future<void> _loadAdvanced() async {
    final api = _api;
    if (api == null) return;
    try {
      final health = await api.systemHealth();
      if (mounted) setState(() => _health = health);
    } on SdkApiException catch (e) {
      if (mounted) {
        setState(() => _health = {
              'error': {'message': e.message}
            });
      }
    }
  }

  Future<void> _confirmResetRobot() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset Robot?'),
        content: const Text(
          'This permanently deletes every saved map and every saved '
          'location on the robot, then disconnects this app and returns it '
          'to the initial setup screen. This cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Reset Robot'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _resetRobot();
  }

  Future<void> _resetRobot() async {
    final connection = context.read<ConnectionProvider>();
    final api = _api;
    if (api == null) return;

    var mapNames = <String>[];
    var locationNames = <String>[];
    var missionIds = <String>[];
    var scheduleIds = <String>[];
    try {
      final results = await Future.wait([
        api.listMaps(),
        api.listWaypoints(),
        api.listMissions(),
        api.listSchedules(),
      ]);
      mapNames = results[0] as List<String>;
      locationNames = (results[1] as List<Map<String, dynamic>>)
          .map((l) => l['name'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      missionIds = (results[2] as List<Map<String, dynamic>>)
          .map((m) => m['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      scheduleIds = (results[3] as List<Map<String, dynamic>>)
          .map((s) => s['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "Couldn't read what's on the robot, so nothing was deleted: $e")));
      return;
    }

    if (!mounted) return;
    final progress = ValueNotifier<String>('Starting…');
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: progress,
                builder: (context, text, _) => Text(text),
              ),
            ),
          ],
        ),
      ),
    ));

    // Best-effort per item — one map or location that fails to delete
    // shouldn't stop the rest, but is worth reporting once done.
    var failures = 0;
    for (final name in mapNames) {
      progress.value = 'Deleting map "$name"…';
      try {
        await api.deleteMap(name);
      } catch (_) {
        failures++;
      }
    }
    for (final name in locationNames) {
      progress.value = 'Deleting location "$name"…';
      try {
        await api.deleteWaypoint(name);
      } catch (_) {
        failures++;
      }
    }
    for (final id in missionIds) {
      progress.value = 'Deleting mission "$id"…';
      try {
        await api.deleteMission(id);
      } catch (_) {
        failures++;
      }
    }
    for (final id in scheduleIds) {
      progress.value = 'Deleting schedule "$id"…';
      try {
        await api.deleteSchedule(id);
      } catch (_) {
        failures++;
      }
    }
    progress.value = 'Clearing dock pose…';
    try {
      await api.deleteDockPose();
    } catch (_) {}
    await LocationsController.instance.refresh(api);

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close progress dialog

    if (failures > 0) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Some items failed to delete'),
          content:
              Text('$failures item${failures == 1 ? '' : 's'} could not be '
                  'deleted (the robot may be unreachable for some of them). '
                  'Continue disconnecting and returning to setup anyway?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Stop here')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    await connection.forget();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SplashScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionProvider>();
    final robotIp = connection.robot?.ip;
    if (robotIp != null && (_api == null || _api!.robotIp != robotIp)) {
      _api = SdkApiService(robotIp);
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    final telemetry = context.watch<RobotTelemetryProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Robot Status')),
      body: SafeArea(
        child: robotIp == null
            ? const Center(child: Text('Not connected.'))
            : StreamBuilder<SdkState>(
                initialData: SdkState.unknown,
                stream: SdkStateService(robotIp).watch(),
                builder: (context, snapshot) {
                  final sdkState = snapshot.data ?? SdkState.unknown;
                  final status = deriveRobotStatus(
                      telemetry: telemetry, sdkState: sdkState);
                  final isActive = _isActiveStatus(status);
                  final identityLoading = _info == null && _infoError == null;

                  return CenteredFormColumn(
                    maxWidth: 640,
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      children: [
                        FadeSlideIn(
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
                                            width: 56,
                                            height: 56,
                                            decoration: const BoxDecoration(
                                              gradient:
                                                  AppColors.avatarGradient,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                                Icons.smart_toy_rounded,
                                                color: AppColors.textOnPrimary,
                                                size: 30),
                                          ),
                                          Positioned(
                                            right: -1,
                                            bottom: -1,
                                            child: Container(
                                              padding: const EdgeInsets.all(2),
                                              decoration: const BoxDecoration(
                                                  color: AppColors.surface,
                                                  shape: BoxShape.circle),
                                              child: StatusPulseDot(
                                                  color: status.color,
                                                  live: isActive,
                                                  size: 10),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: AppSpacing.md),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(connection.robot!.name,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleLarge),
                                            AnimatedSwitcher(
                                              duration: AppMotion.fast,
                                              child: Text(
                                                  'Online · ${status.label}',
                                                  key: ValueKey(status),
                                                  style: const TextStyle(
                                                      color: AppColors
                                                          .textSecondary)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: AppSpacing.xl),
                                  _row(
                                      context,
                                      'Serial',
                                      identityLoading
                                          ? null
                                          : (_info?['robot'] as Map?)?['serial']
                                                  ?.toString() ??
                                              '—'),
                                  _row(
                                      context,
                                      'Model',
                                      identityLoading
                                          ? null
                                          : _info?['model']?.toString() ?? '—'),
                                  _row(context, 'IP address',
                                      connection.robot!.ip),
                                  _row(
                                    context,
                                    'Uptime',
                                    identityLoading
                                        ? null
                                        : (_info?['uptime_sec'] is num
                                            ? _formatUptime(
                                                (_info!['uptime_sec'] as num)
                                                    .toDouble())
                                            : '—'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 60),
                          child: Row(
                            children: [
                              Expanded(
                                child: _StatTile(
                                  icon: Icons.battery_full_rounded,
                                  label: 'Battery',
                                  value: AnimatedMetricText(
                                    value: telemetry.batteryPercentage,
                                    formatter: (v) => '${v.round()}%',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: _StatTile(
                                  icon: Icons.speed_rounded,
                                  label: 'Speed',
                                  value: AnimatedMetricText(
                                    value: telemetry.linearSpeedMps?.abs(),
                                    formatter: (v) =>
                                        '${v.toStringAsFixed(2)} m/s',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 100),
                          child: Row(
                            children: [
                              Expanded(
                                child: _StatTile(
                                  icon: Icons.tune_rounded,
                                  label: 'Mode',
                                  value: _AnimatedText(sdkState.mode ?? '—',
                                      Theme.of(context).textTheme.titleMedium),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: _StatTile(
                                  icon: Icons.place_rounded,
                                  label: 'Current Location',
                                  value: _AnimatedText(
                                      _nearestLocation(telemetry) ?? 'Unknown',
                                      Theme.of(context).textTheme.titleMedium),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 140),
                          child: Card(
                            child: Column(
                              children: [
                                ListTile(
                                  title: const Text('View Advanced Info'),
                                  subtitle: const Text(
                                      'Per-subsystem health from the robot'),
                                  trailing: AnimatedRotation(
                                    turns: _showAdvanced ? 0.25 : 0,
                                    duration: AppMotion.fast,
                                    child:
                                        const Icon(Icons.chevron_right_rounded),
                                  ),
                                  onTap: () {
                                    setState(
                                        () => _showAdvanced = !_showAdvanced);
                                    if (_showAdvanced && _health == null) {
                                      _loadAdvanced();
                                    }
                                  },
                                ),
                                AnimatedSize(
                                  duration: AppMotion.medium,
                                  curve: AppMotion.settle,
                                  alignment: Alignment.topCenter,
                                  child: _showAdvanced
                                      ? _AdvancedInfo(health: _health)
                                      : const SizedBox(width: double.infinity),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_infoError != null &&
                            _infoError!.isUnreachable) ...[
                          const SizedBox(height: AppSpacing.md),
                          const Text(
                            "Identity and uptime need navpro-sdk.service — it isn't reachable right now.",
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 180),
                          child: Card(
                            color: AppColors.danger.withValues(alpha: 0.05),
                            child: ListTile(
                              leading: const Icon(Icons.restart_alt_rounded,
                                  color: AppColors.danger),
                              title: const Text('Reset Robot',
                                  style: TextStyle(color: AppColors.danger)),
                              subtitle: const Text(
                                  'Delete all maps and locations, then '
                                  'disconnect and return to setup'),
                              onTap: _confirmResetRobot,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  String? _nearestLocation(RobotTelemetryProvider telemetry) {
    final locations = _locations;
    if (locations == null || telemetry.poseX == null || telemetry.poseY == null) {
      return null;
    }
    String? nearestName;
    double nearestDist = double.infinity;
    for (final loc in locations) {
      if (loc['x'] is! num || loc['y'] is! num) continue;
      final d = sqrt(pow((loc['x'] as num) - telemetry.poseX!, 2) +
          pow((loc['y'] as num) - telemetry.poseY!, 2));
      if (d < nearestDist) {
        nearestDist = d;
        nearestName = loc['name'] as String?;
      }
    }
    return (nearestName != null && nearestDist <= 1.0) ? nearestName : null;
  }

  String _formatUptime(double sec) {
    final d = Duration(seconds: sec.round());
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }

  /// A row that shows a skeleton line instead of the value while it's
  /// unknown (`value == null`), rather than a "—" that would look
  /// indistinguishable from "the robot genuinely has none".
  Widget _row(BuildContext context, String label, String? value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary)),
            const Spacer(),
            value == null
                ? const SkeletonBox(width: 90, height: 13)
                : Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
}

bool _isActiveStatus(RobotStatus status) => switch (status) {
      RobotStatus.moving ||
      RobotStatus.mapping ||
      RobotStatus.missionInProgress ||
      RobotStatus.charging =>
        true,
      RobotStatus.idle || RobotStatus.charged => false,
    };

/// A plain crossfade for categorical (non-numeric) values — Mode, Current
/// Location — where a tween wouldn't mean anything but a hard cut still
/// reads as a jump rather than an update.
class _AnimatedText extends StatelessWidget {
  const _AnimatedText(this.text, this.style);

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.fast,
      child: Text(text,
          key: ValueKey(text), style: style, overflow: TextOverflow.ellipsis),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(
      {required this.icon, required this.label, required this.value});

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

class _AdvancedInfo extends StatelessWidget {
  const _AdvancedInfo({required this.health});

  final Map<String, dynamic>? health;

  @override
  Widget build(BuildContext context) {
    if (health == null) {
      return const Padding(
        padding:
            EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: Column(
          children: [
            SkeletonBox(width: double.infinity, height: 16),
            SizedBox(height: 10),
            SkeletonBox(width: double.infinity, height: 16),
            SizedBox(height: 10),
            SkeletonBox(width: double.infinity, height: 16),
          ],
        ),
      );
    }
    if (health!['error'] != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        child: Text((health!['error'] as Map)['message'].toString(),
            style: const TextStyle(color: AppColors.textSecondary)),
      );
    }
    final sources =
        (health!['sources'] as Map?)?.cast<String, dynamic>() ?? const {};
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
      child: Column(
        children: [
          for (final (i, entry) in sources.entries.indexed)
            FadeSlideIn(
              delay: Duration(milliseconds: 40 * i),
              offset: 6,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      (entry.value as Map)['ok'] == true
                          ? Icons.check_circle_rounded
                          : Icons.error_rounded,
                      size: 16,
                      color: (entry.value as Map)['ok'] == true
                          ? AppColors.success
                          : AppColors.danger,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(entry.key)),
                    Text(
                      (entry.value as Map)['age_sec'] != null
                          ? '${((entry.value as Map)['age_sec'] as num).toStringAsFixed(1)}s ago'
                          : 'no data',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
