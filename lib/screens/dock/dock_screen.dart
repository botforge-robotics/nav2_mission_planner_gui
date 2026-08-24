import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../modals/bookmark.dart';
import '../../providers/connection_provider.dart';
import '../../providers/live_telemetry_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/docking_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// Dock & Charge screen — a thin view over the existing `DockingService`
/// singleton, per the plan's §2 mapping: docking is currently exposed only
/// as inline actions on the Navigation screen (toolbar button + bookmark
/// tooltip); this gives it a dedicated, standalone home. No new ROS
/// plumbing — `DockingService` already exposes everything needed.
///
/// Shows real data only: charge % and dock status come from
/// `LiveTelemetryProvider`/`DockingService`. The reference design's
/// voltage/current readout and charge-cycle history aren't shown — this
/// app has no telemetry for either (BatteryState doesn't carry a cycle
/// count, and no voltage/current field is currently read anywhere) rather
/// than fabricating numbers.
class DockScreen extends StatefulWidget {
  const DockScreen({super.key});

  @override
  State<DockScreen> createState() => _DockScreenState();
}

class _DockScreenState extends State<DockScreen> {
  String? _activeMap;
  bool _actionInFlight = false;

  @override
  void initState() {
    super.initState();
    DockingService.instance.initialize(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveActiveMap());
  }

  Future<void> _resolveActiveMap() async {
    final connection = Provider.of<ConnectionProvider>(context, listen: false);
    final map = await connection.detectActiveMapName();
    if (!mounted) return;
    setState(() => _activeMap = map);
  }

  Future<void> _dock(Bookmark dockBookmark) async {
    setState(() => _actionInFlight = true);
    try {
      final result = await DockingService.instance.dock(
        x: dockBookmark.positionX,
        y: dockBookmark.positionY,
        theta: dockBookmark.theta,
      );
      if (!mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dock failed or was cancelled')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Dock failed: $e')));
    } finally {
      if (mounted) setState(() => _actionInFlight = false);
    }
  }

  Future<void> _undock() async {
    setState(() => _actionInFlight = true);
    try {
      final result = await DockingService.instance.undockInPlace();
      if (!mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Undock failed or was cancelled')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Undock failed: $e')));
    } finally {
      if (mounted) setState(() => _actionInFlight = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.lightTheme,
      child: Builder(builder: (context) {
        final theme = Theme.of(context);
        return Container(
          color: AppColors.lightBackground,
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: AnimatedBuilder(
                    animation: DockingService.instance,
                    builder: (context, _) {
                      final docking = DockingService.instance;
                      final settings = context.watch<SettingsProvider>();
                      final telemetry = context.watch<LiveTelemetryProvider>();
                      final dockBookmark = _activeMap != null
                          ? settings.getDockBookmark(_activeMap!)
                          : null;

                      final statusColor = docking.statusColor(context);

                      return Column(
                        children: [
                          Text('Dock & Charge',
                              style: theme.textTheme.headlineSmall),
                          const SizedBox(height: AppSpacing.xl),
                          _ChargeRing(
                            percent: telemetry.batteryPercent,
                            color: statusColor,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            docking.isDocked ? 'Charging' : docking.statusLabel,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(color: statusColor),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            docking.isFault
                                ? 'The last dock/undock action failed — safe to retry'
                                : (docking.isDocked
                                    ? 'Docked and charging'
                                    : (docking.isBusy
                                        ? 'In progress…'
                                        : 'Not docked')),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: docking.isDocked || docking.isBusy
                                ? FilledButton.icon(
                                    onPressed:
                                        (_actionInFlight || docking.isBusy)
                                            ? null
                                            : _undock,
                                    icon: docking.isBusy
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : const Icon(Icons.eject),
                                    label: Text(
                                        docking.isBusy ? 'Working…' : 'Undock'),
                                  )
                                : FilledButton.icon(
                                    onPressed: (_actionInFlight ||
                                            dockBookmark == null)
                                        ? null
                                        : () => _dock(dockBookmark),
                                    icon: const Icon(Icons.ev_station),
                                    label: Text(dockBookmark == null
                                        ? 'No dock set for this map'
                                        : 'Send to Dock'),
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Big circular charge indicator — battery % from LiveTelemetryProvider,
/// ring color reflects dock/charge state.
class _ChargeRing extends StatelessWidget {
  final double? percent;
  final Color color;

  const _ChargeRing({required this.percent, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = percent;
    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 160,
            height: 160,
            child: CircularProgressIndicator(
              value: p == null ? null : (p / 100).clamp(0.0, 1.0),
              strokeWidth: 10,
              backgroundColor: AppColors.lightSurfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Text(
            p == null ? '—' : '${p.round()}%',
            style: theme.textTheme.headlineLarge,
          ),
        ],
      ),
    );
  }
}
