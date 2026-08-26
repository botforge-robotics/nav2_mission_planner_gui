import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ros2_api/ros2_api.dart';

import '../../providers/connection_provider.dart';
import '../../providers/robot_telemetry_provider.dart';
import '../../services/locations_controller.dart';
import '../../services/map_layers_controller.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../utils/action_feedback.dart';
import '../../utils/localize_at_dock.dart';
import '../../widgets/design/fade_in.dart';
import '../../widgets/design/hud_chip.dart';
import '../../widgets/map/not_localized_banner.dart';
import '../../widgets/map/occupancy_grid_view.dart';
import '../../widgets/navigation/dock_action_sheet.dart';
import '../../widgets/navigation/go_to_confirm_sheet.dart';
import '../../widgets/teleop/drive_pad.dart';
import '../maps/map_view_screen.dart';

/// Reference §9 (Teleoperation): a free-drag analog joystick plus dedicated
/// rotate-left/rotate-right buttons for direct drive; saved-location pins
/// on the live map are tappable to send the robot there (see
/// LocationsController), replacing what used to be a separate "where to
/// go" list section below the controls. Direct drive publishes via
/// navpromini_sdk's POST /motion/velocity (handlers/motion.py) rather than a
/// raw cmd_vel publish over rosbridge — the SDK route applies the robot's
/// real speed clamps server-side and is the one path this reference
/// experience is built around; a raw-topic fallback would silently bypass
/// those clamps. This screen therefore needs navpro-sdk.service running,
/// same as Locations/Missions — shown as an honest unreachable state if not.
///
/// No camera view here: the robot does have a camera, but it's wired up for
/// AprilTag dock detection only (`docking_method: apriltag` in the SDK's
/// own system/info) — there's no image topic or HTTP route exposing it as
/// a general live feed (confirmed against the real robot's topic list:
/// only `/scan`, no `/camera/...`). That space is used for a live,
/// interactive map view instead — the same [OccupancyGridView] Create
/// Map's live view uses, with the same x/y/heading HUD chip — genuinely
/// useful while driving, unlike a placeholder for a feed that doesn't
/// exist.
class TeleopScreen extends StatefulWidget {
  const TeleopScreen({super.key});

  @override
  State<TeleopScreen> createState() => _TeleopScreenState();
}

class _TeleopScreenState extends State<TeleopScreen> {
  String? _motionError;
  bool _docking = false;
  bool _undocking = false;

  /// True while a finger is actively dragging the joystick — disables the
  /// controls list's own scroll physics for that duration (see
  /// DrivePad.onDragActiveChanged) so a touch that starts on the stick
  /// can't also scroll the page underneath it on a touch device.
  bool _joystickDragging = false;

  bool _requestedLocations = false;
  ({double x, double y, double theta})? _dockPose;

  SdkApiService? get _api {
    final ip = context.read<ConnectionProvider>().robot?.ip;
    return ip == null ? null : SdkApiService(ip);
  }

  /// Same fallback Map View's own live view uses — see the doc on
  /// [OccupancyGridView.dockPoseOverride] for why the live `/dock_pose`
  /// topic alone isn't reliable enough to draw the dock pin from.
  Future<void> _loadDockPose() async {
    final api = _api;
    if (api == null) return;
    final dock = await fetchDockPose(api);
    if (!mounted || dock == null) return;
    setState(() => _dockPose = dock);
  }

  Future<void> _onVelocity(double linear, double angular) async {
    try {
      await _api?.setVelocity(linear, angular);
      if (_motionError != null && mounted) setState(() => _motionError = null);
    } on SdkApiException catch (e) {
      if (mounted) setState(() => _motionError = e.message);
    }
  }

  Future<void> _stop() async {
    try {
      await _api?.stopMotion();
    } on SdkApiException {
      // Best-effort — the ~0.5s cmd_vel_teleop expiry (see motion.py) already
      // stops the robot even if this explicit stop doesn't land.
    }
  }

  Future<void> _dock() async {
    final api = _api;
    if (api == null) return;
    setState(() => _docking = true);
    await retryOnFailure(
      context: context,
      actionLabel: 'Docking',
      attempt: (attemptNumber) async {
        try {
          await api.dock();
        } on SdkApiException catch (e) {
          if (!mounted) return ActionOutcome.failed;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              e.isUnreachable
                  ? "Docking needs navpro-sdk.service — it isn't reachable right now."
                  : e.message,
            ),
          ));
          return ActionOutcome.failed;
        }
        if (!mounted) return ActionOutcome.timedOut;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(attemptNumber == 1
                ? 'Heading to the dock…'
                : 'Heading to the dock… (attempt $attemptNumber)')));
        // Awaited now, not fire-and-forget — _docking stays true (blocking
        // the rest of the controls, see _DockBusyOverlay) for the whole
        // operation, not just until the goal is accepted.
        return _watchDockOutcome(api);
      },
    );
    if (mounted) setState(() => _docking = false);
  }

  Future<void> _undock() async {
    final api = _api;
    if (api == null) return;
    setState(() => _undocking = true);
    await retryOnFailure(
      context: context,
      actionLabel: 'Undocking',
      attempt: (attemptNumber) async {
        try {
          await api.undock();
        } on SdkApiException catch (e) {
          if (!mounted) return ActionOutcome.failed;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              e.isUnreachable
                  ? "Undocking needs navpro-sdk.service — it isn't reachable right now."
                  : e.message,
            ),
          ));
          return ActionOutcome.failed;
        }
        if (!mounted) return ActionOutcome.timedOut;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(attemptNumber == 1
                ? 'Undocking…'
                : 'Undocking… (attempt $attemptNumber)')));
        return _watchDockOutcome(api);
      },
    );
    if (mounted) setState(() => _undocking = false);
  }

  /// True for the whole dock/undock operation — from the moment it's
  /// requested until the outcome is known (or the watch times out) — not
  /// just while the HTTP request is in flight. Drives _DockBusyOverlay,
  /// which blocks the joystick/rotate/stop/go-to controls for that entire
  /// window: those all publish real velocity/navigation commands, and
  /// letting one fire mid-dock is a real way to fight the docking maneuver
  /// itself rather than just a confusing UI state.
  bool get _dockBusy => _docking || _undocking;
  String get _dockBusyLabel => _docking ? 'Docking…' : 'Undocking…';

  Future<ActionOutcome> _watchDockOutcome(SdkApiService api) =>
      watchAndReportOutcome(
        context: context,
        fetchStatus: api.dockStatus,
        isDone: (s) =>
            const {'docked', 'undocked', 'failed'}.contains(s['operation']),
        isOk: (s) => s['operation'] != 'failed',
        describe: (s) => s['operation'] == 'failed'
            ? 'Dock operation failed'
                '${s['message'] != null && (s['message'] as String).isNotEmpty ? ' — ${s['message']}' : '.'}'
            : s['operation'] == 'docked'
                ? 'Docked.'
                : 'Undocked.',
        timeout: const Duration(seconds: 60),
      );

  Future<void> _goTo(Map<String, dynamic> location) async {
    final api = _api;
    final ros2 = context.read<ConnectionProvider>().ros2;
    if (api == null || ros2 == null) return;
    if (location['x'] is! num || location['y'] is! num) return;
    final telemetry = context.read<RobotTelemetryProvider>();
    await showGoToConfirmSheet(
      context: context,
      ros2: ros2,
      api: api,
      locationName: location['name'] as String? ?? '',
      targetX: (location['x'] as num).toDouble(),
      targetY: (location['y'] as num).toDouble(),
      currentX: telemetry.poseX,
      currentY: telemetry.poseY,
    );
  }

  void _onDockTapped() {
    final api = _api;
    if (api == null) return;
    showDockActionSheet(context: context, api: api, dockPose: _dockPose);
  }

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionProvider>();
    final robotIp = connection.robot?.ip;
    if (!_requestedLocations && robotIp != null) {
      _requestedLocations = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final api = _api;
        if (api != null) LocationsController.instance.refresh(api);
        _loadDockPose();
      });
    }
    final telemetry = context.watch<RobotTelemetryProvider>();
    final ros2 = connection.ros2;
    final isMobile = Breakpoints.of(context) == DeviceClass.mobile;

    return Scaffold(
      appBar: AppBar(title: const Text('Teleoperation')),
      body: SafeArea(
        child: robotIp == null
            ? const Center(child: Text('Not connected.'))
            : Column(
                children: [
                  // Pulled out of the controls card and, on mobile, flush
                  // with the screen edges (no rounding, no side padding) —
                  // the map is the primary thing being looked at while
                  // driving, so it gets the full width rather than sitting
                  // inset inside a card like a secondary element.
                  ValueListenableBuilder<List<Map<String, dynamic>>?>(
                    valueListenable: LocationsController.instance,
                    builder: (context, locations, _) => _LiveMapSection(
                      ros2: ros2,
                      telemetry: telemetry,
                      api: _api,
                      fullBleed: isMobile,
                      locations: locations,
                      dockPoseOverride: _dockPose,
                      onLocationTap: _goTo,
                      onDockTap: _onDockTapped,
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        CenteredFormColumn(
                          maxWidth: 720,
                          child: ListView(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            // Disabled for the duration of a joystick drag — see
                            // _joystickDragging's own doc comment.
                            physics: _joystickDragging
                                ? const NeverScrollableScrollPhysics()
                                : null,
                            children: [
                              FadeSlideIn(
                                child: Card(
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.all(AppSpacing.lg),
                                    child: Column(
                                      children: [
                                        DrivePad(
                                          onVelocity: _onVelocity,
                                          onStop: _stop,
                                          onDragActiveChanged: (active) =>
                                              setState(() =>
                                                  _joystickDragging = active),
                                        ),
                                        if (_motionError != null) ...[
                                          const SizedBox(height: AppSpacing.md),
                                          Text(
                                            _motionError!
                                                    .contains('unreachable')
                                                ? "Direct drive needs navpro-sdk.service — it isn't reachable right now."
                                                : _motionError!,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                color: AppColors.danger,
                                                fontSize: 12),
                                          ),
                                        ],
                                        const SizedBox(height: AppSpacing.lg),
                                        Row(
                                          children: [
                                            Expanded(
                                              flex: 3,
                                              child: ElevatedButton.icon(
                                                onPressed: _stop,
                                                style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        AppColors.danger),
                                                icon: const Icon(
                                                    Icons.stop_circle_rounded),
                                                label: const Text('STOP ROBOT'),
                                              ),
                                            ),
                                            const SizedBox(
                                                width: AppSpacing.sm),
                                            Expanded(
                                              flex: 3,
                                              child: _DockUndockControl(
                                                docking: _docking,
                                                undocking: _undocking,
                                                onDock: _dock,
                                                onUndock: _undock,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                              FadeSlideIn(
                                delay: const Duration(milliseconds: 60),
                                child: _GoToLocationCard(onGoTo: _goTo),
                              ),
                            ],
                          ),
                        ),
                        if (_dockBusy)
                          Positioned.fill(
                            child: _DockBusyOverlay(label: _dockBusyLabel),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// The live map header — full-bleed (no rounding, no side margin) on
/// mobile per [fullBleed], contained like every other card on larger
/// screens where edge-to-edge would look stretched rather than
/// intentional. Owns the same x/y/heading + speed HUD chips and
/// not-localized banner Create Map's own live view uses.
class _LiveMapSection extends StatelessWidget {
  const _LiveMapSection({
    required this.ros2,
    required this.telemetry,
    required this.api,
    required this.fullBleed,
    required this.locations,
    required this.dockPoseOverride,
    required this.onLocationTap,
    required this.onDockTap,
  });

  final Ros2? ros2;
  final RobotTelemetryProvider telemetry;
  final SdkApiService? api;
  final bool fullBleed;
  final List<Map<String, dynamic>>? locations;
  final ({double x, double y, double theta})? dockPoseOverride;

  /// Tapping a location or dock pin sends the robot there — the map's own
  /// pins are now the way to do that from Teleop, replacing the separate
  /// "where to go" list section that used to sit below the controls.
  final void Function(Map<String, dynamic>) onLocationTap;
  final VoidCallback onDockTap;

  @override
  Widget build(BuildContext context) {
    final map = SizedBox(
      height: 280,
      width: double.infinity,
      child: Container(
        color: AppColors.surfaceSunken,
        child: ros2 == null
            ? const Center(child: Text('Not connected.'))
            : Stack(
                children: [
                  Positioned.fill(
                    // The layer selection is shared app-wide (see
                    // MapLayersController) — this map shows whatever's
                    // toggled on from any screen, not a fixed subset.
                    child: ValueListenableBuilder<Set<MapLayer>>(
                      valueListenable: MapLayersController.instance,
                      builder: (context, visibleLayers, _) => OccupancyGridView(
                        ros2: ros2!,
                        interactive: true,
                        showRobot: true,
                        showDock: visibleLayers.contains(MapLayer.dock),
                        showPath: visibleLayers.contains(MapLayer.path),
                        showGlobalCostmap:
                            visibleLayers.contains(MapLayer.globalCostmap),
                        showLocalCostmap:
                            visibleLayers.contains(MapLayer.localCostmap),
                        locations: visibleLayers.contains(MapLayer.locations)
                            ? (locations ?? const [])
                            : const [],
                        dockPoseOverride: dockPoseOverride,
                        onLocationTap: onLocationTap,
                        onDockTap: onDockTap,
                        // The banner below takes over "not localized"
                        // messaging here.
                        showLocalizationBadge: false,
                      ),
                    ),
                  ),
                  if (telemetry.localized)
                    Positioned(
                      left: AppSpacing.sm,
                      top: AppSpacing.sm,
                      child: HudChip(
                        text: 'x: ${telemetry.poseX!.toStringAsFixed(2)}  '
                            'y: ${telemetry.poseY!.toStringAsFixed(2)}  '
                            'θ: ${(telemetry.poseTheta ?? 0).toStringAsFixed(2)} rad',
                      ),
                    )
                  else if (api != null)
                    Positioned(
                      left: AppSpacing.sm,
                      right: AppSpacing.sm,
                      top: AppSpacing.sm,
                      child: NotLocalizedBanner(
                        api: api!,
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
                  // Speed used to be its own SpeedGauge section below the
                  // map — moved up here as a HUD chip so the map itself
                  // gets the freed-up vertical space.
                  Positioned(
                    left: AppSpacing.sm,
                    bottom: AppSpacing.sm,
                    child: HudChip(
                      text: telemetry.linearSpeedMps != null
                          ? '${telemetry.linearSpeedMps!.abs().toStringAsFixed(2)} m/s'
                          : '— m/s',
                    ),
                  ),
                ],
              ),
      ),
    );
    if (fullBleed) return map;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: map,
      ),
    );
  }
}

/// A single pill split down the middle — Dock on the left half, Undock on
/// the right — rather than two separate buttons, since they're mutually
/// exclusive actions on the same control (the robot is either docking or
/// undocking, never both), and a shared pill makes that relationship clear
/// at a glance the way two independent OutlinedButtons wouldn't.
class _DockUndockControl extends StatelessWidget {
  const _DockUndockControl({
    required this.docking,
    required this.undocking,
    required this.onDock,
    required this.onUndock,
  });

  final bool docking;
  final bool undocking;
  final VoidCallback onDock;
  final VoidCallback onUndock;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: _DockUndockHalf(
              icon: Icons.ev_station_rounded,
              label: 'Dock',
              busy: docking,
              onTap: docking || undocking ? null : onDock,
            ),
          ),
          Container(width: 1, color: AppColors.border),
          Expanded(
            child: _DockUndockHalf(
              icon: Icons.logout_rounded,
              label: 'Undock',
              busy: undocking,
              onTap: docking || undocking ? null : onUndock,
            ),
          ),
        ],
      ),
    );
  }
}

class _DockUndockHalf extends StatelessWidget {
  const _DockUndockHalf({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Center(
        child: busy
            ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: AppColors.textPrimary),
                  const SizedBox(width: 6),
                  Text(label,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600)),
                ],
              ),
      ),
    );
  }
}

/// A compact "go to a saved location" control — a dropdown of names plus a
/// Go button, replacing the fuller list card that used to sit here (tapping
/// a pin directly on the live map above is now the other way to do this;
/// this is the quicker one when the location you want isn't currently
/// visible in the map's own viewport).
class _GoToLocationCard extends StatefulWidget {
  const _GoToLocationCard({required this.onGoTo});

  final void Function(Map<String, dynamic>) onGoTo;

  @override
  State<_GoToLocationCard> createState() => _GoToLocationCardState();
}

class _GoToLocationCardState extends State<_GoToLocationCard> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ValueListenableBuilder<List<Map<String, dynamic>>?>(
          valueListenable: LocationsController.instance,
          builder: (context, locations, _) {
            final list = locations ?? const <Map<String, dynamic>>[];
            final names = [for (final l in list) l['name'] as String? ?? ''];
            if (_selected != null && !names.contains(_selected)) {
              _selected = null;
            }
            return Row(
              children: [
                const Icon(Icons.place_rounded, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selected,
                    isExpanded: true,
                    hint: Text(list.isEmpty
                        ? 'No saved locations yet'
                        : 'Where should the robot go?'),
                    decoration: const InputDecoration(
                        border: InputBorder.none, isDense: true),
                    items: [
                      for (final name in names)
                        DropdownMenuItem(value: name, child: Text(name)),
                    ],
                    onChanged: list.isEmpty
                        ? null
                        : (v) => setState(() => _selected = v),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: _selected == null
                      ? null
                      : () => widget.onGoTo(
                          list.firstWhere((l) => l['name'] == _selected)),
                  child: const Text('Go'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Blocks the controls below the live map while a dock/undock is actually
/// in progress — a scrim over the whole controls area (not just disabling
/// individual buttons) is the simpler fix for a real problem: the joystick,
/// rotate buttons, STOP, and the go-to picker all publish real
/// velocity/navigation commands, and one firing mid-maneuver is a genuine
/// way to fight the dock/undock itself, not just a confusing UI state.
class _DockBusyOverlay extends StatelessWidget {
  const _DockBusyOverlay({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface.withValues(alpha: 0.85),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              height: 32,
              width: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(label,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: AppSpacing.xs),
            const Text('Controls are disabled until this finishes.',
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
