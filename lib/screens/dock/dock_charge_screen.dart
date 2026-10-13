import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../providers/robot_telemetry_provider.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/design/breathing_opacity.dart';
import '../../widgets/design/fade_in.dart';
import 'dock_position_editor_screen.dart';

/// Reference §11 (Dock & Charge). The big circular percentage stays on the
/// core telemetry path (RobotTelemetryProvider), same as before; everything
/// else here — voltage, current, an estimated time-to-full, and "Contact
/// confirmed" — comes from the SDK's own `/state/battery` (its real BMS
/// pack read, not just the percentage rosbridge already gives this app) and
/// `/dock/status`. Dock actions go through the SDK's docking endpoints
/// (handlers/docking.py) — real dock_manager action calls, not a rosbridge
/// passthrough this app would have to reimplement.
///
/// Two things the reference mockup shows that aren't built here, on
/// purpose: "Recent Charge Cycles" (navpromini_sdk keeps no charge-cycle
/// history — no endpoint for it, and fabricating rows would violate this
/// app's own honest-empty-state convention, see the Dashboard's Alerts card
/// for the same principle) and a numeric "Dock Alignment" percentage (the
/// AprilTag detector reports visible/not-visible plus a pixel offset while
/// *approaching*, not an "aligned" score once actually docked — showing a
/// fake percentage there would be worse than the real signals this screen
/// shows instead: AprilTag visibility, and "Contact confirmed" from
/// charging current, which handlers/docking.py's own DockStatusHandler
/// documents as the actual ground truth for physical connection).
class DockChargeScreen extends StatefulWidget {
  const DockChargeScreen({super.key});

  @override
  State<DockChargeScreen> createState() => _DockChargeScreenState();
}

class _DockChargeScreenState extends State<DockChargeScreen> {
  Timer? _poll;
  Map<String, dynamic>? _dockStatus;
  Map<String, dynamic>? _batteryDetail;
  SdkApiException? _statusError;
  bool _busy = false;
  String? _actionError;

  SdkApiService? get _api {
    final ip = context.read<ConnectionProvider>().robot?.ip;
    return ip == null ? null : SdkApiService(ip);
  }

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final api = _api;
    if (api == null) return;
    try {
      final results = await Future.wait([api.dockStatus(), api.battery()]);
      if (!mounted) return;
      setState(() {
        _dockStatus = results[0];
        _batteryDetail = results[1]['detail'] as Map<String, dynamic>?;
        _statusError = null;
      });
    } on SdkApiException catch (e) {
      if (!mounted) return;
      setState(() => _statusError = e);
    }
  }

  /// A rough, clearly-labeled estimate from the real pack read — not a
  /// robot-reported figure. remain_capacity_ah / soc_percent backs out an
  /// implied full-pack capacity (the BMS doesn't report that directly), the
  /// gap to 100% divided by the live charge current gives hours remaining.
  /// Only shown while actually charging at a measurable current — a CC/CV
  /// charge curve tapers near full, so this reads as "roughly" rather than
  /// exact, same honesty as the route ETA elsewhere in this app.
  Duration? get _estimatedTimeToFull {
    final telemetry = context.read<RobotTelemetryProvider>();
    final detail = telemetry.batteryDetail ?? _batteryDetail;
    if (detail == null) return null;
    final soc = (detail['soc_percent'] as num?)?.toDouble();
    final remainAh = (detail['remain_capacity_ah'] as num?)?.toDouble();
    final currentA = (detail['pack_current_a'] as num?)?.toDouble();
    if (soc == null || remainAh == null || currentA == null) return null;
    if (soc <= 0 || soc >= 99.5 || currentA <= 0.05) return null;
    final fullCapacityAh = remainAh / (soc / 100);
    final hoursToFull = (fullCapacityAh - remainAh) / currentA;
    if (hoursToFull.isNaN || hoursToFull.isInfinite || hoursToFull <= 0) {
      return null;
    }
    return Duration(minutes: (hoursToFull * 60).round());
  }

  Future<void> _act(Future<void> Function(SdkApiService) action) async {
    final api = _api;
    if (api == null) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await action(api);
      await _refresh();
    } on SdkApiException catch (e) {
      if (!mounted) return;
      try {
        final status = await api.dockStatus();
        final op = status['operation'] as String? ?? '';
        if (const {
          'docking',
          'staging',
          'searching',
          'servo',
          'undocking',
          'docked',
          'undocked'
        }.contains(op)) {
          await _refresh();
          return;
        }
      } catch (_) {}
      setState(() => _actionError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final robotIp = context.watch<ConnectionProvider>().robot?.ip;
    final telemetry = context.watch<RobotTelemetryProvider>();
    final battery = telemetry.batteryPercentage;
    final charging = telemetry.chargeStatus == ChargeStatus.charging;
    final activeDetail = telemetry.batteryDetail ?? _batteryDetail;
    final operation = _dockStatus?['operation'] as String?;
    final busy = _busy || operation == 'docking' || operation == 'undocking';
    final tagVisible = _dockStatus?['tag_visible'] == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dock & Charge'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Edit Dock Position',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const DockPositionEditorScreen(),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: robotIp == null
            ? const Center(child: Text('Not connected.'))
            : CenteredFormColumn(
                maxWidth: 520,
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    FadeSlideIn(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Column(
                            children: [
                              SizedBox(
                                height: 168,
                                width: 168,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    SizedBox(
                                      height: 168,
                                      width: 168,
                                      child: TweenAnimationBuilder<double>(
                                        tween: Tween(
                                          begin: battery != null
                                              ? battery / 100
                                              : 0,
                                          end: battery != null
                                              ? battery / 100
                                              : 0,
                                        ),
                                        duration: AppMotion.resolveDuration(context, AppMotion.slow),
                                        curve: AppMotion.settle,
                                        builder: (context, animated, _) =>
                                            CircularProgressIndicator(
                                          value: battery != null
                                              ? animated.clamp(0, 1)
                                              : null,
                                          strokeWidth: 12,
                                          strokeCap: StrokeCap.round,
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest,
                                          color: charging
                                              ? AppColors.success
                                              : (battery != null && battery < 20
                                                  ? AppColors.danger
                                                  : AppColors.of(context).primary),
                                        ),
                                      ),
                                    ),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          battery != null
                                              ? telemetry.formatBatteryPercent()
                                              : '—',
                                          style: AppTextStyles.metricLarge.copyWith(
                                            fontFeatures: const [FontFeature.tabularFigures()],
                                          ),
                                        ),
                                        if (charging)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: BreathingOpacity(
                                              active: true,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: AppColors.success.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: const Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.bolt_rounded, color: AppColors.success, size: 14),
                                                    SizedBox(width: 2),
                                                    Text(
                                                      'CHARGING',
                                                      style: TextStyle(
                                                        color: AppColors.success,
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                        letterSpacing: 0.5,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              AnimatedSwitcher(
                                duration: AppMotion.resolveDuration(context, AppMotion.fast),
                                child: Container(
                                  key: ValueKey(_statusLabel(telemetry.dockStatus, charging)),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: (charging ? AppColors.success : AppColors.of(context).textSecondary)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: (charging ? AppColors.success : AppColors.of(context).border)
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        charging
                                            ? Icons.bolt_rounded
                                            : Icons.power_off_rounded,
                                        size: 15,
                                        color: charging
                                            ? AppColors.success
                                            : AppColors.of(context).textSecondary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _statusLabel(
                                            telemetry.dockStatus, charging),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                          color: charging
                                              ? AppColors.success
                                              : Theme.of(context).colorScheme.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 30),
                      child: _BatteryStatsRow(
                        timeToFull: _estimatedTimeToFull,
                        charging: charging,
                        voltage: (activeDetail?['pack_voltage_v'] as num?)
                            ?.toDouble(),
                        current: (activeDetail?['pack_current_a'] as num?)
                            ?.toDouble(),
                        healthy: activeDetail?['failure_bits'] == null
                            ? null
                            : (activeDetail!['failure_bits'] as num) == 0,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 60),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Dock Status',
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: AppSpacing.sm),
                              if (_statusError != null)
                                Text(
                                  _statusError!.isUnreachable
                                      ? "Needs navpro-sdk.service — it isn't reachable right now."
                                      : _statusError!.message,
                                  style: const TextStyle(
                                      color: AppColors.textSecondary),
                                )
                              else ...[
                                // "Contact confirmed" from charging current —
                                // handlers/docking.py's own DockStatusHandler
                                // documents that as the real ground truth for
                                // physical connection, not dock_manager's own
                                // reported state alone (a robot pushed onto
                                // the dock by hand can disagree with it).
                                _DockStatusRow(
                                  ok: charging,
                                  label: charging
                                      ? 'Contact confirmed'
                                      : 'No contact',
                                  known: _dockStatus != null,
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                _DockStatusRow(
                                  ok: tagVisible,
                                  label: tagVisible
                                      ? 'AprilTag visible'
                                      : 'AprilTag not visible',
                                  known: _dockStatus != null,
                                  neutral: true,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_actionError != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(_actionError!,
                          style: const TextStyle(color: AppColors.danger)),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 100),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              icon: const Icon(Icons.logout_rounded, size: 18),
                              onPressed: busy
                                  ? null
                                  : () => _act((api) => api.undock()),
                              label: const Text('Undock'),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              icon: busy
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white),
                                    )
                                  : const Icon(Icons.ev_station_rounded, size: 18),
                              onPressed:
                                  busy ? null : () => _act((api) => api.dock()),
                              label: const Text('Send to Dock'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  String _statusLabel(String? dockStatus, bool charging) {
    if (dockStatus == null) return charging ? 'Charging' : 'Not docked';
    final normalized = dockStatus.toLowerCase();
    if (normalized.contains('dock') && charging) return 'Docked · Charging';
    if (normalized.contains('dock')) return 'Docked';
    return charging ? 'Charging' : 'Not docked';
  }
}

/// Three real BMS readings side by side — voltage and current always shown
/// once known, time-to-full only while it can be meaningfully estimated
/// (see [_DockChargeScreenState._estimatedTimeToFull]'s own doc), a health
/// chip only when the pack's own failure-bits field is known.
class _BatteryStatsRow extends StatelessWidget {
  const _BatteryStatsRow({
    required this.timeToFull,
    required this.charging,
    required this.voltage,
    required this.current,
    required this.healthy,
  });

  final Duration? timeToFull;
  final bool charging;
  final double? voltage;
  final double? current;
  final bool? healthy;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    icon: Icons.timer_outlined,
                    label: 'Time to Full',
                    value: charging && timeToFull != null
                        ? _formatDuration(timeToFull!)
                        : '—',
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: _Stat(
                    icon: Icons.bolt_outlined,
                    label: 'Voltage',
                    value: voltage != null
                        ? '${voltage!.toStringAsFixed(1)} V'
                        : '—',
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: _Stat(
                    icon: Icons.electric_meter_outlined,
                    label: 'Current',
                    value: current != null
                        ? '${current!.toStringAsFixed(1)} A'
                        : '—',
                  ),
                ),
              ],
            ),
            if (healthy != null) ...[
              const SizedBox(height: AppSpacing.sm),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Text(
                    'Battery Health (BMS)',
                    style: TextStyle(color: AppColors.of(context).textSecondary, fontSize: 13),
                  ),
                  const Spacer(),
                  Icon(
                    healthy! ? Icons.check_circle_rounded : Icons.error_rounded,
                    size: 16,
                    color: healthy! ? AppColors.success : AppColors.danger,
                  ),
                  const SizedBox(width: 4),
                  Text(healthy! ? 'Optimal' : 'Fault Detected',
                      style: TextStyle(
                          color:
                              healthy! ? AppColors.success : AppColors.danger,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inMinutes < 1) return '<1m';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.of(context).surfaceSunken,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: AppColors.of(context).primary),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTextStyles.metric.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.of(context).textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _DockStatusRow extends StatelessWidget {
  const _DockStatusRow({
    required this.ok,
    required this.label,
    required this.known,
    this.neutral = false,
  });

  final bool ok;
  final String label;
  final bool known;

  /// True for signals that are informational either way (AprilTag
  /// visibility isn't "bad" when false once actually docked) — shown in
  /// neutral gray instead of red so it doesn't read as a fault.
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final color = !known
        ? colors.textSecondary
        : ok
            ? AppColors.success
            : (neutral ? colors.textSecondary : AppColors.danger);
    return Row(
      children: [
        Icon(
          !known
              ? Icons.help_outline_rounded
              : ok
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
          size: 18,
          color: color,
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(known ? label : 'Checking…', style: TextStyle(color: color, fontSize: 13)),
      ],
    );
  }
}
