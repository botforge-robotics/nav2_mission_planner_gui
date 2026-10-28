import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Floating D-Pad HUD for precision micro-adjustments of robot/waypoint coordinates
/// (5mm position resolution) and orientation (1° angle resolution).
class MicroAdjustmentHud extends StatefulWidget {
  const MicroAdjustmentHud({
    super.key,
    required this.onNudge,
    this.onRotate,
    this.title = 'Micro Adjustment',
    this.showRotation = true,
  });

  /// Called when an arrow button is tapped, with (dx, dy) in map meters.
  final void Function(double dx, double dy) onNudge;

  /// Called when a rotation button is tapped, with dTheta in radians.
  final void Function(double dTheta)? onRotate;

  final String title;
  final bool showRotation;

  @override
  State<MicroAdjustmentHud> createState() => _MicroAdjustmentHudState();
}

class _MicroAdjustmentHudState extends State<MicroAdjustmentHud> {
  // Distance step options: 5mm (0.005m), 25mm (0.025m), 100mm (0.10m)
  double _distStep = 0.005; // 5 mm default

  // Angle step options: 1° (0.0175 rad), 5°, 15°
  double _angleStepDeg = 1.0; // 1 degree default

  bool _minimized = false;

  double get _angleStepRad => _angleStepDeg * pi / 180.0;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Card(
      elevation: 6,
      shadowColor: Colors.black45,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.border, width: 1),
      ),
      color: colors.surface.withValues(alpha: 0.95),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            InkWell(
              onTap: () => setState(() => _minimized = !_minimized),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tune_rounded, size: 16, color: colors.primary),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      widget.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _minimized ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                      size: 16,
                      color: colors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
            if (!_minimized) ...[
              const SizedBox(height: AppSpacing.xs),

              // Step size selector chips
              Wrap(
                spacing: 4,
                children: [
                  _stepChip('5 mm', 0.005),
                  _stepChip('25 mm', 0.025),
                  _stepChip('10 cm', 0.10),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),

              // D-Pad Directional Controls
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // D-Pad cross
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Up
                        Positioned(
                          top: 0,
                          child: _ArrowBtn(
                            icon: Icons.keyboard_arrow_up_rounded,
                            tooltip: 'Nudge +Y (${(_distStep * 1000).round()}mm) - Hold to repeat',
                            onTap: () => widget.onNudge(0, _distStep),
                          ),
                        ),
                        // Down
                        Positioned(
                          bottom: 0,
                          child: _ArrowBtn(
                            icon: Icons.keyboard_arrow_down_rounded,
                            tooltip: 'Nudge -Y (${(_distStep * 1000).round()}mm) - Hold to repeat',
                            onTap: () => widget.onNudge(0, -_distStep),
                          ),
                        ),
                        // Left
                        Positioned(
                          left: 0,
                          child: _ArrowBtn(
                            icon: Icons.keyboard_arrow_left_rounded,
                            tooltip: 'Nudge -X (${(_distStep * 1000).round()}mm) - Hold to repeat',
                            onTap: () => widget.onNudge(-_distStep, 0),
                          ),
                        ),
                        // Right
                        Positioned(
                          right: 0,
                          child: _ArrowBtn(
                            icon: Icons.keyboard_arrow_right_rounded,
                            tooltip: 'Nudge +X (${(_distStep * 1000).round()}mm) - Hold to repeat',
                            onTap: () => widget.onNudge(_distStep, 0),
                          ),
                        ),
                        // Center indicator
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: colors.surfaceSunken,
                            shape: BoxShape.circle,
                            border: Border.all(color: colors.border),
                          ),
                          child: Center(
                            child: Icon(Icons.control_camera_rounded,
                                size: 14, color: colors.textTertiary),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Rotation Controls if enabled
                  if (widget.showRotation && widget.onRotate != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    const SizedBox(
                      height: 100,
                      child: VerticalDivider(width: 1),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Wrap(
                          spacing: 4,
                          children: [
                            _degChip('1°', 1.0),
                            _degChip('5°', 5.0),
                            _degChip('15°', 15.0),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ArrowBtn(
                              icon: Icons.rotate_left_rounded,
                              tooltip: 'Rotate CCW +${_angleStepDeg.toInt()}° - Hold to repeat',
                              onTap: () => widget.onRotate!(_angleStepRad),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            _ArrowBtn(
                              icon: Icons.rotate_right_rounded,
                              tooltip: 'Rotate CW -${_angleStepDeg.toInt()}° - Hold to repeat',
                              onTap: () => widget.onRotate!(-_angleStepRad),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stepChip(String label, double val) {
    final selected = (_distStep - val).abs() < 0.0001;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 10)),
      selected: selected,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      onSelected: (_) => setState(() => _distStep = val),
    );
  }

  Widget _degChip(String label, double val) {
    final selected = (_angleStepDeg - val).abs() < 0.1;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 10)),
      selected: selected,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      onSelected: (_) => setState(() => _angleStepDeg = val),
    );
  }
}

class _ArrowBtn extends StatefulWidget {
  const _ArrowBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_ArrowBtn> createState() => _ArrowBtnState();
}

class _ArrowBtnState extends State<_ArrowBtn> {
  Timer? _initialTimer;
  Timer? _periodicTimer;

  void _start() {
    widget.onTap();
    _stop();
    _initialTimer = Timer(const Duration(milliseconds: 320), () {
      _periodicTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        widget.onTap();
      });
    });
  }

  void _stop() {
    _initialTimer?.cancel();
    _initialTimer = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTapDown: (_) => _start(),
        onTapUp: (_) => _stop(),
        onTapCancel: _stop,
        child: Material(
          color: colors.surfaceSunken,
          shape: CircleBorder(side: BorderSide(color: colors.border)),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 20, color: colors.textPrimary),
          ),
        ),
      ),
    );
  }
}
