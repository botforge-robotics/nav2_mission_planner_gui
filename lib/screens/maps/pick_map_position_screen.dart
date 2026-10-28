import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../providers/robot_telemetry_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/map/micro_adjustment_hud.dart';
import '../../widgets/map/occupancy_grid_view.dart';

/// Redesigned Robot Location Picker Screen with 5mm D-Pad precision
/// and 1-degree orientation controls.
class PickMapPositionScreen extends StatefulWidget {
  const PickMapPositionScreen({
    super.key,
    this.initialPose,
    this.title = 'Select Robot Position',
  });

  final ({double x, double y, double theta})? initialPose;
  final String title;

  @override
  State<PickMapPositionScreen> createState() => _PickMapPositionScreenState();
}

class _PickMapPositionScreenState extends State<PickMapPositionScreen> {
  ({double x, double y, double theta})? _draft;

  // Undo history stack for precision adjustments
  final List<({double x, double y, double theta})?> _history = [];

  void _pushHistory() {
    _history.add(_draft);
    if (_history.length > 50) _history.removeAt(0);
  }

  void _undo() {
    if (_history.isEmpty) return;
    final prev = _history.removeLast();
    setState(() {
      _draft = prev;
    });
  }

  @override
  void initState() {
    super.initState();
    _draft = widget.initialPose;
  }

  void _onNudge(double dx, double dy) {
    if (_draft == null) return;
    _pushHistory();
    setState(() {
      _draft = (
        x: _draft!.x + dx,
        y: _draft!.y + dy,
        theta: _draft!.theta,
      );
    });
  }

  void _onRotate(double dTheta) {
    if (_draft == null) return;
    _pushHistory();
    var newTheta = _draft!.theta + dTheta;
    // Normalize to [-pi, pi]
    while (newTheta > pi) {
      newTheta -= 2 * pi;
    }
    while (newTheta < -pi) {
      newTheta += 2 * pi;
    }
    setState(() {
      _draft = (
        x: _draft!.x,
        y: _draft!.y,
        theta: newTheta,
      );
    });
  }

  void _setOrientationPreset(double theta) {
    if (_draft == null) return;
    _pushHistory();
    setState(() {
      _draft = (
        x: _draft!.x,
        y: _draft!.y,
        theta: theta,
      );
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
      _draft = (
        x: p.position.x,
        y: p.position.y,
        theta: yaw,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final ros2 = context.watch<ConnectionProvider>().ros2;
    final telemetry = context.watch<RobotTelemetryProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.undo_rounded),
              tooltip: 'Undo Adjustment',
              onPressed: _undo,
            ),
          if (telemetry.rawPose != null)
            TextButton.icon(
              onPressed: () => _snapToRobot(telemetry),
              icon: const Icon(Icons.my_location_rounded, size: 18),
              label: const Text('Snap to Robot'),
            ),
        ],
      ),
      body: ros2 == null
          ? const Center(child: Text('Not connected to robot.'))
          : Stack(
              children: [
                Positioned.fill(
                  child: OccupancyGridView(
                    ros2: ros2,
                    interactive: true,
                    posePicking: true,
                    showLaserScan: true,
                    draftPoseOverride: _draft,
                    onDraftPose: (x, y, theta) {
                      _pushHistory();
                      setState(() => _draft = (x: x, y: y, theta: theta));
                    },
                  ),
                ),

                // Top Floating Telemetry & Presets Card
                Positioned(
                  top: AppSpacing.sm,
                  left: AppSpacing.md,
                  right: AppSpacing.md,
                  child: Center(
                    child: Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: colors.border),
                      ),
                      color: colors.surface.withValues(alpha: 0.95),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: 8,
                        ),
                        child: _draft == null
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.touch_app_rounded,
                                      size: 16, color: colors.primary),
                                  const SizedBox(width: 8),
                                  Text(
                                    '👉 Tap anywhere on the map to place the robot pose, then fine-tune.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.place_rounded,
                                              size: 15, color: colors.accent),
                                          const SizedBox(width: 4),
                                          Text(
                                            'X: ${_draft!.x.toStringAsFixed(3)} m',
                                            style: const TextStyle(
                                                fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.place_rounded,
                                              size: 15, color: colors.accent),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Y: ${_draft!.y.toStringAsFixed(3)} m',
                                            style: const TextStyle(
                                                fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.navigation_rounded,
                                              size: 15, color: colors.accent),
                                          const SizedBox(width: 4),
                                          Text(
                                            'θ: ${(_draft!.theta * 180 / pi).toStringAsFixed(1)}°',
                                            style: const TextStyle(
                                                fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
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
                                          color: colors.textSecondary,
                                        ),
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
                              ),
                      ),
                    ),
                  ),
                ),

                // Floating 5mm & 1° Micro-Adjustment D-Pad HUD
                if (_draft != null)
                  Positioned(
                    bottom: 84,
                    right: AppSpacing.md,
                    child: MicroAdjustmentHud(
                      title: 'Fine-tune Pose (🎯)',
                      showRotation: true,
                      onNudge: _onNudge,
                      onRotate: _onRotate,
                    ),
                  ),

                // Bottom Action Bar
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border(top: BorderSide(color: colors.border)),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed: _draft == null
                                  ? null
                                  : () => Navigator.of(context).pop(_draft),
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: const Text('Use This Position'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
