import 'dart:async';
import 'dart:math';

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
    this.alreadyMapping = false,
  });

  final bool fromSetup;

  /// When true, mapping is already running on the robot — skip the
  /// `setMode('mapping')` call and go straight to the live mapping view.
  /// Used when the screen is auto-opened by the `/robot_mode` topic
  /// subscription detecting that mapping started externally.
  final bool alreadyMapping;

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

  /// When creating a new map, mapping begins at the charging dock facing
  /// outwards. The initial position of the robot in the map frame defines
  /// the dock position. As the robot drives away, the departure heading sets
  /// the dock angle and the standoff point (0.7m in front of dock).
  ({double x, double y, double theta})? _dockPose;
  ({double x, double y, double theta})? _standoffPose;
  bool _hasMovedAwayFromDock = false;
  double? _mappingStartRx;
  double? _mappingStartRy;

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
    });
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
    // When alreadyMapping, mapping was started externally — just show the view.
    if (widget.fromSetup || widget.alreadyMapping) {
      if (widget.alreadyMapping) {
        // Mapping is already running on the robot — skip setMode, just
        // show the live mapping view immediately.
        setState(() {
          _phase = _Phase.mapping;
        });
      } else {
        await _startMapping();
      }
      return;
    }
    final isDesktop = MediaQuery.sizeOf(context).width >= 800 ||
        Breakpoints.of(context) == DeviceClass.desktop;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _DockInstructionDialog(
        previousMap: _previousMap,
        isDesktop: isDesktop,
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
      context.read<RobotTelemetryProvider>().resetForMapping();
      _dockPose = null;
      _standoffPose = null;
      _hasMovedAwayFromDock = false;
      _mappingStartRx = null;
      _mappingStartRy = null;
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

  bool _velocitySending = false;
  ({double linear, double angular})? _pendingVelocity;

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

    _pendingVelocity = (linear: linear, angular: angular);
    if (_velocitySending) return;
    _velocitySending = true;

    final ip = context.read<ConnectionProvider>().robot?.ip;
    final api = _apiFor(ip);

    while (_pendingVelocity != null) {
      final cmd = _pendingVelocity!;
      _pendingVelocity = null;
      try {
        await api?.setVelocity(cmd.linear, cmd.angular);
      } on SdkApiException {
        // Best-effort
      }
    }
    _velocitySending = false;
  }

  Future<void> _stopMotion() async {
    _pendingVelocity = null;
    final pub = _getCmdVelPublisher();
    final ros2 = _cmdVelRos2;
    if (pub != null && ros2 != null && ros2.status == Status.connected) {
      final stopTwist = geometry_msgs.Twist(
        linear: geometry_msgs.Vector3(x: 0.0, y: 0.0, z: 0.0),
        angular: geometry_msgs.Vector3(x: 0.0, y: 0.0, z: 0.0),
      );
      pub.publish(stopTwist);
      return;
    }
    final ip = context.read<ConnectionProvider>().robot?.ip;
    try {
      await _apiFor(ip)?.stopMotion();
    } on SdkApiException {
      // Best-effort
    }
  }

  Future<void> _cancel() async {
    _dockPose = null;
    _standoffPose = null;
    _hasMovedAwayFromDock = false;
    _mappingStartRx = null;
    _mappingStartRy = null;
    final ip = context.read<ConnectionProvider>().robot?.ip;
    final api = _apiFor(ip);
    if (api == null) return;
    final prevMap = (_previousMap != null &&
            _previousMap != 'default' &&
            _previousMap!.trim().isNotEmpty)
        ? _previousMap
        : null;
    setState(() => _busyMessage = prevMap != null
        ? 'Restoring "$prevMap"…'
        : 'Stopping mapping…');
    try {
      ModeTransitionTracker.instance.startStoppingMapping(
        targetMode: prevMap != null ? 'navigation' : 'idle',
      );
      if (prevMap != null) {
        await api
            .setMode('navigation', map: prevMap)
            .timeout(const Duration(seconds: 25));
      } else {
        await api.setMode('idle').timeout(const Duration(seconds: 15));
      }
      if (!mounted) return;
      context.read<RobotTelemetryProvider>().exitMappingMode();
      Navigator.of(context).pop();
    } on TimeoutException {
      if (!mounted) return;
      context.read<RobotTelemetryProvider>().exitMappingMode();
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

      // Persist dock pose and waypoints for the newly created map
      final dp = _dockPose ?? (x: 0.0, y: 0.0, theta: 0.0);
      final sp = _standoffPose ?? (
        x: dp.x + 0.70 * cos(dp.theta),
        y: dp.y + 0.70 * sin(dp.theta),
        theta: dp.theta,
      );
      final dockAngle = atan2(sp.y - dp.y, sp.x - dp.x);
      final standoffAngle = atan2(dp.y - sp.y, dp.x - sp.x);
      try {
        await api.setDockPose(x: dp.x, y: dp.y, theta: dockAngle);
        await api.saveWaypoint('Charging Dock',
            x: dp.x, y: dp.y, theta: dockAngle, type: 'dock');
        await api.saveWaypoint('Dock Standoff',
            x: sp.x, y: sp.y, theta: standoffAngle, type: 'dock');
      } catch (_) {}

      await api.finishMapping(name, overwrite: overwrite);
      if (!mounted) return;
      context.read<RobotTelemetryProvider>().exitMappingMode();
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
        // finishMapping already stopped SLAM (mode → idle) and the map data
        // was physically saved by map_saver — only the "is it new?" check
        // failed. Re-calling finishMapping would fail with "not_mapping"
        // because SLAM is already down. Instead, re-save via the standalone
        // maps endpoint with overwrite, then activate the map.
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
        if (overwriteConfirmed == true && mounted) {
          await _save(name, overwrite: true);
        }
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

    final rx = telemetry.poseX;
    final ry = telemetry.poseY;
    final rTheta = telemetry.poseTheta ?? 0.0;
    if (rx != null && ry != null) {
      if (_mappingStartRx == null || _mappingStartRy == null) {
        _mappingStartRx = rx;
        _mappingStartRy = ry;
        _dockPose = (x: rx, y: ry, theta: rTheta);
        _standoffPose = (
          x: rx + 0.70 * cos(rTheta),
          y: ry + 0.70 * sin(rTheta),
          theta: rTheta,
        );
      } else if (!_hasMovedAwayFromDock) {
        final dx = rx - _mappingStartRx!;
        final dy = ry - _mappingStartRy!;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist >= 0.25) {
          final depAngle = atan2(dy, dx);
          final dockX = _mappingStartRx!;
          final dockY = _mappingStartRy!;
          _dockPose = (x: dockX, y: dockY, theta: depAngle);
          _standoffPose = (
            x: dockX + 0.70 * cos(depAngle),
            y: dockY + 0.70 * sin(depAngle),
            theta: depAngle,
          );
          _hasMovedAwayFromDock = true;
        }
      }
    }

    return PopScope(
      canPop: _phase != _Phase.mapping,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Create Map'),
          automaticallyImplyLeading: false,
        ),
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
                                                initialPose: null,
                                                showDock: true,
                                                showPath: visibleLayers
                                                    .contains(MapLayer.path),
                                                showGlobalCostmap:
                                                    visibleLayers.contains(
                                                        MapLayer.globalCostmap),
                                                showLocalCostmap:
                                                    visibleLayers.contains(
                                                        MapLayer.localCostmap),
                                                showLaserScan: true,
                                                laserScanTopic: '/scan_filtered',
                                                dockPoseOverride: _dockPose,
                                                standoffPoseOverride: _standoffPose,
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
                            maxLinear: 0.20,
                            maxAngular: 0.45,
                            rotateAngular: 0.35,
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

class _DockInstructionDialog extends StatelessWidget {
  const _DockInstructionDialog({
    required this.previousMap,
    required this.isDesktop,
  });

  final String? previousMap;
  final bool isDesktop;

  Widget _buildTip(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isDesktop ? 900 : 480,
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.charging_station_rounded,
                        color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Place Robot at Dock',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          'Position robot before creating map',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Image.asset(
                            isDesktop
                                ? 'assets/desktopDock.png'
                                : 'assets/mobilDockInstruction.png',
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'CHECKLIST BEFORE STARTING:',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            _buildTip(Icons.check_circle_outline_rounded,
                                'Charging dock placed flat against a rigid wall.'),
                            _buildTip(Icons.check_circle_outline_rounded,
                                'Robot positioned on/near dock facing outward into the room.'),
                            _buildTip(Icons.check_circle_outline_rounded,
                                'Leave ≥ 0.5m clearance on sides and 1.0m in front.'),
                          ],
                        ),
                      ),
                      if (previousMap != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Starting SLAM pauses navigation on "$previousMap". You can cancel later to restore it.',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textTertiary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Start Mapping'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

