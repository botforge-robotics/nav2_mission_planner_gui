import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../providers/robot_telemetry_provider.dart';
import '../../services/dock_pose_controller.dart';
import '../../services/locations_controller.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/map/micro_adjustment_hud.dart';
import '../../widgets/map/occupancy_grid_view.dart';

/// Visual Dock & Standoff Position Editor.
///
/// Streamlined workflow:
/// 1. User selects the Dock Station (⚡) position and adjusts its orientation
///    (pointing towards the front of the dock, where the robot approaches from).
/// 2. Standoff Point (🎯) is automatically calculated and locked at exactly 0.70m
///    directly in front of the dock along the dock's forward heading.
/// 3. Orientation can be adjusted via 1-degree precision rotate buttons, presets,
///    or "Snap to Robot".
class DockPositionEditorScreen extends StatefulWidget {
  const DockPositionEditorScreen({super.key});

  @override
  State<DockPositionEditorScreen> createState() =>
      _DockPositionEditorScreenState();
}

class _DockPositionEditorScreenState extends State<DockPositionEditorScreen> {
  ({double x, double y, double theta})? _dockPose;

  bool _saving = false;
  bool _loading = true;

  // Undo history stack
  final List<({double x, double y, double theta})?> _history = [];

  void _pushHistory() {
    _history.add(_dockPose);
    if (_history.length > 50) _history.removeAt(0);
  }

  void _undo() {
    if (_history.isEmpty) return;
    final prev = _history.removeLast();
    setState(() {
      _dockPose = prev;
    });
  }

  SdkApiService? get _api {
    final ip = context.read<ConnectionProvider>().robot?.ip;
    return ip == null ? null : SdkApiService(ip);
  }

  ({double x, double y, double theta})? get _standoffPose {
    if (_dockPose == null) return null;
    const standoffDist = 0.70;
    return (
      x: _dockPose!.x + standoffDist * cos(_dockPose!.theta),
      y: _dockPose!.y + standoffDist * sin(_dockPose!.theta),
      theta: _dockPose!.theta,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadInitialPositions();
  }

  Future<void> _loadInitialPositions() async {
    final api = _api;
    if (api != null) {
      try {
        final dockData = await api.dockPose();
        final x = (dockData['x'] as num?)?.toDouble();
        final y = (dockData['y'] as num?)?.toDouble();
        final theta = (dockData['theta'] as num?)?.toDouble() ?? 0.0;
        if (x != null && y != null) {
          _dockPose = (x: x, y: y, theta: theta);
        }
      } catch (_) {
        // No dock pose configured yet
      }
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _onMapTap(double wx, double wy) {
    _pushHistory();
    setState(() {
      final currentTheta = _dockPose?.theta ?? 0.0;
      _dockPose = (x: wx, y: wy, theta: currentTheta);
    });
  }

  void _onNudge(double dx, double dy) {
    if (_dockPose == null) return;
    _pushHistory();
    setState(() {
      _dockPose = (
        x: _dockPose!.x + dx,
        y: _dockPose!.y + dy,
        theta: _dockPose!.theta,
      );
    });
  }

  void _onRotate(double dTheta) {
    if (_dockPose == null) return;
    _pushHistory();
    var newTheta = _dockPose!.theta + dTheta;
    while (newTheta > pi) {
      newTheta -= 2 * pi;
    }
    while (newTheta < -pi) {
      newTheta += 2 * pi;
    }
    setState(() {
      _dockPose = (
        x: _dockPose!.x,
        y: _dockPose!.y,
        theta: newTheta,
      );
    });
  }

  void _setOrientationPreset(double theta) {
    if (_dockPose == null) return;
    _pushHistory();
    setState(() {
      _dockPose = (x: _dockPose!.x, y: _dockPose!.y, theta: theta);
    });
  }

  void _snapToRobot(RobotTelemetryProvider telemetry) {
    final p = telemetry.rawPose?.pose.pose;
    if (p == null) return;
    _pushHistory();
    final yaw = atan2(
      2 * (p.orientation.w * p.orientation.z + p.orientation.x * p.orientation.y),
      1 - 2 * (p.orientation.y * p.orientation.y + p.orientation.z * p.orientation.z),
    );
    setState(() {
      _dockPose = (x: p.position.x, y: p.position.y, theta: yaw);
    });
  }

  Future<void> _save() async {
    if (_dockPose == null) return;
    final standoff = _standoffPose;
    if (standoff == null) return;

    setState(() => _saving = true);
    final api = _api;
    if (api == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Robot SDK is not connected.')),
      );
      setState(() => _saving = false);
      return;
    }

    try {
      // 1. Set dock pose on robot (this also updates robot's ~/.navpromini_dock_pose.json with 0.70m standoff)
      await api.setDockPose(
        x: _dockPose!.x,
        y: _dockPose!.y,
        theta: _dockPose!.theta,
      );

      // 2. Save/update "Dock Standoff" waypoint
      await api.saveWaypoint(
        'Dock Standoff',
        x: standoff.x,
        y: standoff.y,
        theta: standoff.theta,
        type: 'dock',
      );

      // 3. Save/update "Charging Dock" waypoint
      await api.saveWaypoint(
        'Charging Dock',
        x: _dockPose!.x,
        y: _dockPose!.y,
        theta: _dockPose!.theta,
        type: 'dock',
      );

      // Instantly update shared controllers for immediate live UI feedback
      DockPoseController.instance.update(
        dock: (x: _dockPose!.x, y: _dockPose!.y, theta: _dockPose!.theta),
        standoff: (x: standoff.x, y: standoff.y, theta: standoff.theta),
      );
      await LocationsController.instance.refresh(api);
      await DockPoseController.instance.refresh(api);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dock & Standoff (0.70m) saved successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save dock pose: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final ros2 = context.watch<ConnectionProvider>().ros2;
    final telemetry = context.watch<RobotTelemetryProvider>();
    final standoff = _standoffPose;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dock & Standoff Pose Editor'),
        actions: [
          if (telemetry.rawPose != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: () => _snapToRobot(telemetry),
                icon: const Icon(Icons.my_location_rounded, size: 16),
                label: const Text('Snap to Robot'),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.undo_rounded),
            tooltip: _history.isNotEmpty ? 'Undo (${_history.length})' : 'Undo',
            onPressed: _history.isNotEmpty ? _undo : null,
          ),
          if (_dockPose != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md, left: AppSpacing.xs),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: const Text('Save Positions'),
              ),
            ),
        ],
      ),
      body: ros2 == null
          ? const Center(child: Text('Not connected to robot.'))
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: [
                    // Interactive Map with Dock Editor Layer
                    Positioned.fill(
                      child: OccupancyGridView(
                        ros2: ros2,
                        interactive: true,
                        showDock: false, // hidden in favor of our active editor markers
                        showLaserScan: true,
                        dockEditorMode: true,
                        dockEditorDockPoint: _dockPose == null
                            ? null
                            : (x: _dockPose!.x, y: _dockPose!.y),
                        dockEditorStandoffPoint: standoff == null
                            ? null
                            : (x: standoff.x, y: standoff.y),
                        dockEditorActiveIndex: 0,
                        onDockEditorTap: _onMapTap,
                      ),
                    ),

                    // Top Control / Status HUD Bar
                    Positioned(
                      top: AppSpacing.sm,
                      left: AppSpacing.md,
                      right: AppSpacing.md,
                      child: Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: colors.border),
                        ),
                        color: colors.surface.withValues(alpha: 0.95),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Real-time telemetry readouts
                              Wrap(
                                spacing: 14,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (_dockPose != null) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: colors.stateDocking.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: colors.stateDocking.withValues(alpha: 0.3)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.ev_station_rounded,
                                              size: 15, color: colors.stateDocking),
                                          const SizedBox(width: 5),
                                          Text(
                                            'Dock: (${_dockPose!.x.toStringAsFixed(3)}, ${_dockPose!.y.toStringAsFixed(3)})',
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: colors.stateDocking),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: colors.primary.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: colors.primary.withValues(alpha: 0.3)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.explore_rounded,
                                              size: 15, color: colors.primary),
                                          const SizedBox(width: 5),
                                          Text(
                                            'Heading: ${(_dockPose!.theta * 180 / pi).toStringAsFixed(1)}°',
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: colors.primary),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  if (standoff != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: colors.surfaceSunken,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: colors.border),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.my_location_rounded,
                                              size: 14, color: AppColors.accent),
                                          const SizedBox(width: 5),
                                          Text(
                                            'Auto Standoff: (${standoff.x.toStringAsFixed(3)}, ${standoff.y.toStringAsFixed(3)}) [0.70 m in front]',
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: colors.textPrimary),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (_dockPose == null)
                                    Text(
                                      '👉 Tap anywhere on the map to place the Dock Station.',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: colors.textSecondary),
                                    ),
                                ],
                              ),
                              if (_dockPose != null) ...[
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      'Heading Presets:',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: colors.textSecondary),
                                    ),
                                    ActionChip(
                                      visualDensity: VisualDensity.compact,
                                      label: const Text('0° East (+X)', style: TextStyle(fontSize: 11)),
                                      onPressed: () => _setOrientationPreset(0.0),
                                    ),
                                    ActionChip(
                                      visualDensity: VisualDensity.compact,
                                      label: const Text('90° North (+Y)', style: TextStyle(fontSize: 11)),
                                      onPressed: () => _setOrientationPreset(pi / 2),
                                    ),
                                    ActionChip(
                                      visualDensity: VisualDensity.compact,
                                      label: const Text('180° West (-X)', style: TextStyle(fontSize: 11)),
                                      onPressed: () => _setOrientationPreset(pi),
                                    ),
                                    ActionChip(
                                      visualDensity: VisualDensity.compact,
                                      label: const Text('-90° South (-Y)', style: TextStyle(fontSize: 11)),
                                      onPressed: () => _setOrientationPreset(-pi / 2),
                                    ),
                                    ActionChip(
                                      visualDensity: VisualDensity.compact,
                                      avatar: const Icon(Icons.flip_camera_android_rounded, size: 14),
                                      label: const Text('Flip 180°', style: TextStyle(fontSize: 11)),
                                      onPressed: () => _onRotate(pi),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Floating 5mm Micro-Adjustment D-Pad & Rotation HUD
                    if (_dockPose != null)
                      Positioned(
                        bottom: AppSpacing.md,
                        right: AppSpacing.md,
                        child: MicroAdjustmentHud(
                          title: 'Fine-tune Dock (⚡)',
                          showRotation: true,
                          onNudge: _onNudge,
                          onRotate: _onRotate,
                        ),
                      ),

                    // Bottom info banner
                    Positioned(
                      bottom: AppSpacing.md,
                      left: AppSpacing.md,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: colors.surface.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: colors.border),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _dockPose == null
                                  ? Icons.touch_app_rounded
                                  : Icons.lock_clock_rounded,
                              size: 16,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _dockPose == null
                                  ? 'Tap map to position the Dock Station'
                                  : 'Standoff automatically placed 0.70m in front of dock',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary),
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
