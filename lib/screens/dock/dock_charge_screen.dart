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
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
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
    final detail = _batteryDetail;
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
    final operation = _dockStatus?['operation'] as String?;
    final busy = _busy || operation == 'docking' || operation == 'undocking';
    final tagVisible = _dockStatus?['tag_visible'] == true;

    return Scaffold(
      appBar: AppBar(title: const Text('Dock & Charge')),
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
                                height: 160,
                                width: 160,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    SizedBox(
                                      height: 160,
                                      width: 160,
                                      child: TweenAnimationBuilder<double>(
                                        tween: Tween(
                                          begin: battery != null
                                              ? battery / 100
                                              : 0,
                                          end: battery != null
                                              ? battery / 100
                                              : 0,
                                        ),
                                        duration: AppMotion.slow,
                                        curve: AppMotion.settle,
                                        builder: (context, animated, _) =>
                                            CircularProgressIndicator(
                                          value: battery != null
                                              ? animated.clamp(0, 1)
                                              : null,
                                          strokeWidth: 10,
                                          backgroundColor: AppColors.border,
                                          color: charging
                                              ? AppColors.success
                                              : AppColors.primary,
                                        ),
                                      ),
                                    ),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          battery != null
                                              ? '${battery.round()}%'
                                              : '—',
                                          style: AppTextStyles.metricLarge,
                                        ),
                                        if (charging)
                                          BreathingOpacity(
                                            active: true,
                                            child: const Icon(
                                                Icons.bolt_rounded,
                                                color: AppColors.success,
                                                size: 18),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              AnimatedSwitcher(
                                duration: AppMotion.fast,
                                child: Row(
                                  key: ValueKey(_statusLabel(
                                      telemetry.dockStatus, charging)),
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      charging
                                          ? Icons.bolt_rounded
                                          : Icons.power_off_rounded,
                                      size: 16,
                                      color: charging
                                          ? AppColors.success
                                          : AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _statusLabel(
                                          telemetry.dockStatus, charging),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
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
                        voltage: (_batteryDetail?['pack_voltage_v'] as num?)
                            ?.toDouble(),
                        current: (_batteryDetail?['pack_current_a'] as num?)
                            ?.toDouble(),
                        healthy: _batteryDetail?['failure_bits'] == null
                            ? null
                            : (_batteryDetail!['failure_bits'] as num) == 0,
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
                            child: OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => _act((api) => api.undock()),
                              child: const Text('Undock'),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: ElevatedButton(
                              onPressed:
                                  busy ? null : () => _act((api) => api.dock()),
                              child: busy
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.textOnPrimary),
                                    )
                                  : const Text('Send to Dock'),
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
                    label: 'Time to Full',
                    value: charging && timeToFull != null
                        ? _formatDuration(timeToFull!)
                        : '—',
                  ),
                ),
                Expanded(
                  child: _Stat(
                    label: 'Voltage',
                    value: voltage != null
                        ? '${voltage!.toStringAsFixed(1)} V'
                        : '—',
                  ),
                ),
                Expanded(
                  child: _Stat(
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
                  const Text('Battery Status',
                      style: TextStyle(color: AppColors.textSecondary)),
                  const Spacer(),
                  Icon(
                    healthy! ? Icons.check_circle_rounded : Icons.error_rounded,
                    size: 16,
                    color: healthy! ? AppColors.success : AppColors.danger,
                  ),
                  const SizedBox(width: 4),
                  Text(healthy! ? 'Good' : 'Fault',
                      style: TextStyle(
                          color:
                              healthy! ? AppColors.success : AppColors.danger,
                          fontWeight: FontWeight.w600)),
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
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: AppTextStyles.metric),
        const SizedBox(height: 2),
        Text(label,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ],
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
    final color = !known
        ? AppColors.textSecondary
        : ok
            ? AppColors.success
            : (neutral ? AppColors.textSecondary : AppColors.danger);
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
        Text(known ? label : 'Checking…', style: TextStyle(color: color)),
      ],
    );
  }
}
