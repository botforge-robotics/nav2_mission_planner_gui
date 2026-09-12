import 'package:flutter/material.dart';
import 'package:geometry_msgs/msg.dart' as geometry_msgs;
import 'package:provider/provider.dart';
import 'package:ros2_api/ros2_api.dart';

import '../../providers/connection_provider.dart';
import '../../providers/robot_telemetry_provider.dart';
import '../../services/map_layers_controller.dart';
import '../../services/mode_transition_tracker.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../utils/localize_at_dock.dart';
import '../../widgets/design/hud_chip.dart';
import '../../widgets/map/occupancy_grid_view.dart';
import '../../widgets/teleop/drive_pad.dart';
import '../setup/setup_complete_screen.dart';

/// The "Import / Create Map" flow: starts a real SLAM mapping session
/// (`POST /mode {mode: "mapping"}`), shows the map being built live off the
/// same `/map` topic every other map view uses, and finishes with the
/// atomic FINISH_MAPPING call (`POST /mapping/finish`) — stop SLAM, save,
/// switch navigation onto the new map, one call instead of three.
///
/// Mapping and navigation can't run at once (both own the map->odom
/// transform — see mode.py's own module docstring), so this screen
/// confirms before starting, and remembers whatever map was active before
/// so "Cancel" can put navigation back the way it found it rather than
/// just leaving the robot idle. The confirmation also nudges the operator to
/// place the robot at its dock before starting — wherever mapping begins is
/// what SLAM (and this app's own dock-pose save flow) will later treat as
/// the dock's position in the new map.
///
/// The live map view embeds the same [DrivePad] Teleop uses (driving the
/// robot around is the whole point of a mapping session) plus a small HUD —
/// live x/y/heading top-left, speed bottom-left — so the operator doesn't
/// have to glance at a different screen while building the map.
class CreateMapScreen extends StatefulWidget {
  const CreateMapScreen({
    super.key,
    this.fromSetup = false,
  });

  final bool fromSetup;

  @override
  State<CreateMapScreen> createState() => _CreateMapScreenState();
}

class _CreateMapScreenState extends State<CreateMapScreen> {
  _Phase _phase = _Phase.confirming;
  String? _previousMap;
  String? _error;

  /// Non-null while a slow mode-switch (cancel → restore previous map, or
  /// finish → stop SLAM + save + switch navigation) is in flight — both can
  /// legitimately take up to a couple of minutes server-side (see
  /// SdkApiService's own timeout comments), so this drives a full busy
  /// overlay with a message specific to which one is running, rather than
  /// leaving the screen looking merely unresponsive.
  String? _busyMessage;
  bool get _busy => _busyMessage != null;

  ({double x, double y, double theta})? _dockPose;

  SdkApiService? _api;

  SdkApiService? _apiFor(String? ip) {
    if (ip == null) return null;
    if (_api == null || _api!.robotIp != ip) _api = SdkApiService(ip);
    return _api;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _confirmStart();
      _loadDockPose();
    });
  }

  /// Same fallback Map View's own live view uses — see the doc on
  /// [OccupancyGridView.dockPoseOverride] for why the live `/dock_pose`
  /// topic alone isn't reliable enough to draw the dock pin from.
  Future<void> _loadDockPose() async {
    final ip = context.read<ConnectionProvider>().robot?.ip;
    final api = _apiFor(ip);
    if (api == null) return;
    final dock = await fetchDockPose(api);
    if (!mounted || dock == null) return;
    setState(() => _dockPose = dock);
  }

  Future<void> _confirmStart() async {
    final ip = context.read<ConnectionProvider>().robot?.ip;
    final api = _apiFor(ip);
    if (api == null) return;

    // Remember what's currently running so Cancel can restore it.
    try {
      final mode = await api.modeStatus();
      _previousMap = mode['map'] as String?;
    } on SdkApiException {
      // Non-fatal — Cancel just falls back to idle if this couldn't be read.
    }

    if (!mounted) return;

    // When launched from the onboarding setup flow, operator already reviewed
    // dock instructions on the dedicated setup screen and chose "Create Map".
    if (widget.fromSetup) {
      await _startMapping();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start Mapping?'),
        content: Text(
          '${_previousMap != null ? 'This stops navigation on "$_previousMap" and starts a new mapping session. You can cancel later to go back to navigation on that map.\n\n' : 'This starts a new mapping session.\n\n'}'
          'Place the robot at its dock before starting — wherever mapping '
          "begins is encoded as this map's dock position.",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Start Mapping')),
        ],
      ),
    );

    if (!mounted) return;
    if (confirmed != true) {
      Navigator.of(context).pop();
      return;
    }
    await _startMapping();
  }

  Future<void> _startMapping() async {
    final ip = context.read<ConnectionProvider>().robot?.ip;
    final api = _apiFor(ip);
    if (api == null) return;
    setState(() {
      _busyMessage = 'Starting mapping…';
      _error = null;
    });
    try {
      await api.setMode('mapping');
      if (!mounted) return;
      setState(() {
        _phase = _Phase.mapping;
        _busyMessage = null;
      });
    } on SdkApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busyMessage = null;
        _error = e.isUnreachable
            ? "Creating a map needs navpro-sdk.service — it isn't reachable right now."
            : e.message;
      });
    }
  }

  Publisher<geometry_msgs.Twist>? _cmdVelPub;
  Ros2? _cmdVelRos2;

  Publisher<geometry_msgs.Twist>? _getCmdVelPublisher() {
    final ros2 = context.read<ConnectionProvider>().ros2;
    if (ros2 == null) {
      _cmdVelPub?.shutdown();
      _cmdVelPub = null;
      _cmdVelRos2 = null;
      return null;
    }
    if (_cmdVelRos2 != ros2 || _cmdVelPub == null) {
      _cmdVelPub?.shutdown();
      _cmdVelRos2 = ros2;
      _cmdVelPub = Publisher<geometry_msgs.Twist>(
        name: '/cmd_vel_teleop',
        type: geometry_msgs.Twist().fullType,
        ros2: ros2,
      );
    }
    return _cmdVelPub;
  }

  @override
  void dispose() {
    _cmdVelPub?.shutdown();
    super.dispose();
  }

  Future<void> _onVelocity(double linear, double angular) async {
    final pub = _getCmdVelPublisher();
    final ros2 = _cmdVelRos2;
    if (pub != null && ros2 != null && ros2.status == Status.connected) {
      final twist = geometry_msgs.Twist(
        linear: geometry_msgs.Vector3(x: linear, y: 0.0, z: 0.0),
        angular: geometry_msgs.Vector3(x: 0.0, y: 0.0, z: angular),
      );
      pub.publish(twist);
      return;
    }

    final ip = context.read<ConnectionProvider>().robot?.ip;
    final api = _apiFor(ip);
    try {
      await api?.setVelocity(linear, angular);
    } on SdkApiException {
      // Best-effort, same as Teleop's own drive pad — no need to interrupt
      // an active mapping session over one dropped velocity tick.
    }
  }

  Future<void> _stopMotion() async {
    final pub = _getCmdVelPublisher();
    final ros2 = _cmdVelRos2;
    if (pub != null && ros2 != null && ros2.status == Status.connected) {
      final stopTwist = geometry_msgs.Twist(
        linear: geometry_msgs.Vector3(x: 0.0, y: 0.0, z: 0.0),
        angular: geometry_msgs.Vector3(x: 0.0, y: 0.0, z: 0.0),
      );
      pub.publish(stopTwist);
    }
    final ip = context.read<ConnectionProvider>().robot?.ip;
    try {
      await _apiFor(ip)?.stopMotion();
    } on SdkApiException {
      // Best-effort — cmd_vel_teleop's own ~0.5s expiry already stops the
      // robot even if this explicit stop doesn't land.
    }
  }

  Future<void> _cancel() async {
    final ip = context.read<ConnectionProvider>().robot?.ip;
    final api = _apiFor(ip);
    if (api == null) return;
    setState(() => _busyMessage = _previousMap != null
        ? 'Restoring "$_previousMap" — this can take up to a minute…'
        : 'Stopping mapping…');
    try {
      ModeTransitionTracker.instance.startStoppingMapping(
        targetMode: _previousMap != null ? 'navigation' : 'idle',
      );
      if (_previousMap != null) {
        await api.setMode('navigation', map: _previousMap);
      } else {
        await api.setMode('idle');
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } on SdkApiException catch (e) {
      if (!mounted) return;
      ModeTransitionTracker.instance.clear();
      setState(() {
        _busyMessage = null;
        _error = e.message;
      });
    }
  }

  Future<void> _finish() async {
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _NameMapDialog(),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    await _save(name.trim(), overwrite: false);
  }

  Future<void> _save(String name, {required bool overwrite}) async {
    final ip = context.read<ConnectionProvider>().robot?.ip;
    final api = _apiFor(ip);
    if (api == null) return;
    setState(() {
      _busyMessage =
          'Saving "$name" and switching navigation onto it — this can take a few minutes…';
      _error = null;
    });
    try {
      ModeTransitionTracker.instance.startStoppingMapping(
        targetMode: 'navigation',
      );
      await api.finishMapping(name, overwrite: overwrite);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Saved "$name" and switched navigation onto it.')));
      if (widget.fromSetup) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => SetupCompleteScreen(createdMapName: name),
          ),
          (route) => false,
        );
      } else {
        Navigator.of(context).pop(name);
      }
    } on SdkApiException catch (e) {
      if (!mounted) return;
      ModeTransitionTracker.instance.clear();
      if (e.code == 'map_exists') {
        setState(() => _busyMessage = null);
        final overwriteConfirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Map Already Exists'),
            content: Text('A map named "$name" already exists. Replace it?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Replace')),
            ],
          ),
        );
        if (overwriteConfirmed == true) await _save(name, overwrite: true);
        return;
      }
      setState(() {
        _busyMessage = null;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ros2 = context.watch<ConnectionProvider>().ros2;
    final telemetry = context.watch<RobotTelemetryProvider>();

    return PopScope(
      canPop: _phase != _Phase.mapping,
      child: Scaffold(
        appBar: AppBar(title: const Text('Create Map')),
        body: SafeArea(
          child: switch (_phase) {
            _Phase.confirming => Center(
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                size: 48, color: AppColors.danger),
                            const SizedBox(height: AppSpacing.md),
                            Text(_error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: AppColors.textSecondary)),
                            const SizedBox(height: AppSpacing.md),
                            TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Close')),
                          ],
                        ),
                      )
                    : const CircularProgressIndicator(),
              ),
            _Phase.mapping => Stack(
                children: [
                  CenteredFormColumn(
                    maxWidth: 720,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.cardRadius),
                              child: Container(
                                color: AppColors.surfaceSunken,
                                child: ros2 == null
                                    ? const Center(
                                        child: Text('Not connected.'))
                                    : Stack(
                                        children: [
                                          Positioned.fill(
                                            // The layer selection is shared
                                            // app-wide (see
                                            // MapLayersController) — this
                                            // map shows whatever's toggled
                                            // on from any screen.
                                            child: ValueListenableBuilder<
                                                Set<MapLayer>>(
                                              valueListenable:
                                                  MapLayersController.instance,
                                              builder:
                                                  (context, visibleLayers, _) =>
                                                      OccupancyGridView(
                                                ros2: ros2,
                                                interactive: true,
                                                showRobot: true,
                                                showLocalizationBadge: false,
                                                isMapping: true,
                                                initialPose: telemetry.rawPose ??
                                                    telemetry.rawOdomPose,
                                                showDock: visibleLayers
                                                    .contains(MapLayer.dock),
                                                showPath: visibleLayers
                                                    .contains(MapLayer.path),
                                                showGlobalCostmap:
                                                    visibleLayers.contains(
                                                        MapLayer.globalCostmap),
                                                showLocalCostmap:
                                                    visibleLayers.contains(
                                                        MapLayer.localCostmap),
                                                dockPoseOverride: _dockPose,
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            left: AppSpacing.sm,
                                            top: AppSpacing.sm,
                                            child: HudChip(
                                              text: telemetry.poseX != null &&
                                                      telemetry.poseY != null
                                                  ? 'x: ${telemetry.poseX!.toStringAsFixed(2)}  '
                                                      'y: ${telemetry.poseY!.toStringAsFixed(2)}  '
                                                      'θ: ${(telemetry.poseTheta ?? 0).toStringAsFixed(2)} rad'
                                                  : 'x: 0.00  y: 0.00  θ: 0.00 rad',
                                            ),
                                          ),
                                          Positioned(
                                            left: AppSpacing.sm,
                                            bottom: AppSpacing.sm,
                                            child: HudChip(
                                              text: telemetry.linearSpeedMps !=
                                                      null
                                                  ? '${telemetry.linearSpeedMps!.abs().toStringAsFixed(2)} m/s'
                                                  : '— m/s',
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          DrivePad(
                            onVelocity: _onVelocity,
                            onStop: _stopMotion,
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Text(_error!,
                                style:
                                    const TextStyle(color: AppColors.danger)),
                          ],
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _busy ? null : _cancel,
                                  child: const Text('Cancel Mapping'),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _busy ? null : _finish,
                                  child: const Text('Finish & Save'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_busyMessage != null)
                    Container(
                      color: AppColors.surface.withValues(alpha: 0.85),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: AppSpacing.md),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.lg),
                              child: Text(
                                _busyMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
          },
        ),
      ),
    );
  }
}

enum _Phase { confirming, mapping }

class _NameMapDialog extends StatefulWidget {
  @override
  State<_NameMapDialog> createState() => _NameMapDialogState();
}

class _NameMapDialogState extends State<_NameMapDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save Map'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration:
            const InputDecoration(hintText: 'Map name, e.g. Ground Floor'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: const Text('Save')),
      ],
    );
  }
}
