import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';

enum _RotateDir { left, right }

/// The drive control shared by Teleop and Create Map's embedded controls: a
/// free-drag analog joystick for continuous linear+angular drive, plus two
/// small dedicated rotate-in-place buttons (left/right) for a quick spin
/// without needing to hold the stick off-center. This widget only emits
/// velocity via [onVelocity]/[onStop] — each caller wires it to its own
/// SdkApiService instance.
class DrivePad extends StatefulWidget {
  const DrivePad({
    super.key,
    required this.onVelocity,
    required this.onStop,
    this.onDragActiveChanged,
    this.maxLinear = defaultMaxLinear,
    this.maxAngular = defaultMaxAngular,
    this.rotateAngular = defaultRotateAngular,
  });

  /// Called immediately on press/drag, then repeatedly (every 150ms —
  /// comfortably inside cmd_vel_teleop's own ~0.5s expiry window) for as
  /// long as the stick is held off-center or a rotate button is held.
  final void Function(double linear, double angular) onVelocity;

  /// Called once when the stick returns to center / a rotate button is
  /// released.
  final VoidCallback onStop;

  /// Fires true the instant a finger touches down on the joystick OR a
  /// rotate button, false when it lifts.
  final ValueChanged<bool>? onDragActiveChanged;

  /// Maximum forward/backward speed on full joystick deflection (m/s).
  final double maxLinear;

  /// Maximum turning speed on full joystick deflection (rad/s).
  final double maxAngular;

  /// Turning speed for dedicated rotate-in-place buttons (rad/s).
  final double rotateAngular;

  /// Reduced default speeds for smooth, controlled indoor teleoperation:
  /// - Linear: 0.22 m/s (down from 0.35 m/s)
  /// - Angular (joystick): 0.50 rad/s (~28.6 deg/s, down from 1.2 rad/s)
  /// - In-place rotation buttons: 0.40 rad/s (~22.9 deg/s, down from 1.2 rad/s)
  static const defaultMaxLinear = 0.22;
  static const defaultMaxAngular = 0.50;
  static const defaultRotateAngular = 0.40;

  @override
  State<DrivePad> createState() => _DrivePadState();
}

class _DrivePadState extends State<DrivePad> {
  Timer? _timer;
  Offset _stick = Offset.zero; // -1..1 on both axes
  _RotateDir? _rotating;

  void _onStickPanStart(DragStartDetails d, Offset center, double radius) {
    // onDragActiveChanged already fired from the joystick's own
    // Listener.onPointerDown, ahead of gesture-arena resolution — see the
    // field doc on DrivePad.onDragActiveChanged for why that's necessary.
    _timer?.cancel();
    _timer =
        Timer.periodic(const Duration(milliseconds: 150), (_) => _sendStick());
    _updateStick(d.localPosition, center, radius);
  }

  void _onStickPanUpdate(DragUpdateDetails d, Offset center, double radius) =>
      _updateStick(d.localPosition, center, radius);

  // [center]/[radius] describe the *visual* track, not the larger invisible
  // touch target around it (see _Joystick's own doc comment) — so the knob
  // still clamps to the drawn circle and the stick fraction is still
  // relative to the track's true radius even when the finger was accepted
  // slightly outside it.
  void _updateStick(Offset local, Offset center, double radius) {
    var delta = local - center;
    if (delta.distance > radius) {
      delta = Offset.fromDirection(delta.direction, radius);
    }
    setState(() => _stick = Offset(delta.dx / radius, delta.dy / radius));
    _sendStick();
  }

  void _sendStick() {
    final linear = (-_stick.dy) * widget.maxLinear;
    final angular = (-_stick.dx) * widget.maxAngular;
    widget.onVelocity(linear, angular);
  }

  void _onStickPanEnd(DragEndDetails d) {
    // onDragActiveChanged(false) fires from the joystick's own
    // Listener.onPointerUp/onPointerCancel instead — see above.
    _timer?.cancel();
    setState(() => _stick = Offset.zero);
    widget.onStop();
  }

  void _startRotate(_RotateDir dir) {
    setState(() => _rotating = dir);
    _sendRotate();
    _timer?.cancel();
    _timer =
        Timer.periodic(const Duration(milliseconds: 150), (_) => _sendRotate());
  }

  void _sendRotate() {
    final dir = _rotating;
    if (dir == null) return;
    widget.onVelocity(
        0.0,
        dir == _RotateDir.left
            ? widget.rotateAngular
            : -widget.rotateAngular);
  }

  void _endRotate() {
    _timer?.cancel();
    if (_rotating == null) return;
    setState(() => _rotating = null);
    widget.onStop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // One horizontal row, joystick centered: rotate-left / joystick /
    // rotate-right — rather than the rotate buttons stacked to one side, so
    // the whole control reads as a single balanced unit. FittedBox+
    // scaleDown (with the Row sized to its own natural width via
    // mainAxisSize.min) shrinks the whole control on a narrow phone screen
    // instead of overflowing — the row's natural width (joystick + two
    // buttons + gaps) is wider than some phones' available space at full
    // size.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _RoundButton(
            icon: Icons.rotate_left_rounded,
            size: 48,
            active: _rotating == _RotateDir.left,
            onStart: () => _startRotate(_RotateDir.left),
            onEnd: _endRotate,
            onDragActiveChanged: widget.onDragActiveChanged,
          ),
          const SizedBox(width: AppSpacing.lg),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Joystick(
                stick: _stick,
                onPanStart: _onStickPanStart,
                onPanUpdate: _onStickPanUpdate,
                onPanEnd: _onStickPanEnd,
                onDragActiveChanged: widget.onDragActiveChanged,
              ),
              const SizedBox(height: 6),
              const Text('Drag to drive',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(width: AppSpacing.lg),
          _RoundButton(
            icon: Icons.rotate_right_rounded,
            size: 48,
            active: _rotating == _RotateDir.right,
            onStart: () => _startRotate(_RotateDir.right),
            onEnd: _endRotate,
            onDragActiveChanged: widget.onDragActiveChanged,
          ),
        ],
      ),
    );
  }
}

/// The joystick surface itself: a sunken circular track (layered-surface
/// treatment, matching the map preview's inset frame) with a knob that
/// tracks the drag precisely, plus a small press-scale — the knob grows
/// ~12% the instant a drag begins and eases back on release, so the touch
/// itself has tactile feedback distinct from the knob's position tracking.
///
/// The GestureDetector's own hit region is deliberately bigger than the
/// drawn circle (see [_hitSlop]) — a thumb reaching for the stick very
/// commonly lands a few pixels outside the painted track, and a touch that
/// starts even slightly outside a hit-tested widget's bounds never reaches
/// its recognizer at all: it falls straight through to whatever's behind
/// it (Teleop's own scrollable controls list), so the joystick would look
/// dead — knob frozen — while the screen scrolled underneath the thumb
/// instead. Padding the invisible touch target out past the visual edge is
/// the same "hit slop" idea Material uses to keep small icon buttons at a
/// 48dp minimum tap target without drawing them that big.
class _Joystick extends StatefulWidget {
  const _Joystick({
    required this.stick,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    this.onDragActiveChanged,
  });

  final Offset stick;
  final void Function(DragStartDetails, Offset center, double radius)
      onPanStart;
  final void Function(DragUpdateDetails, Offset center, double radius)
      onPanUpdate;
  final void Function(DragEndDetails) onPanEnd;
  final ValueChanged<bool>? onDragActiveChanged;

  static const _size = 180.0;
  static const _radius = _size / 2;

  /// Extra invisible touch margin around the drawn circle — see the class
  /// doc above.
  static const _hitSlop = 32.0;
  static const _hitRadius = _radius + _hitSlop;
  static const _hitCenter = Offset(_hitRadius, _hitRadius);

  @override
  State<_Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<_Joystick>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(vsync: this, duration: AppMotion.instant);
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Outer box stays exactly _size — same footprint DrivePad's FittedBox
    // measures as before, so the hit-slop margin below doesn't make the
    // whole control scale down any more aggressively on a narrow phone
    // than it already did. The larger touch target is a Positioned
    // overflowing that box (Clip.none) rather than a bigger box, so it's
    // invisible to layout and only affects hit testing.
    return SizedBox(
      height: _Joystick._size,
      width: _Joystick._size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: _press,
            builder: (context, _) => CustomPaint(
              size: const Size(_Joystick._size, _Joystick._size),
              painter: _JoystickPainter(
                  stick: widget.stick, knobScale: 1 + _press.value * 0.12),
            ),
          ),
          Positioned(
            left: -_Joystick._hitSlop,
            top: -_Joystick._hitSlop,
            right: -_Joystick._hitSlop,
            bottom: -_Joystick._hitSlop,
            child: Listener(
              // Pointer routing happens before the gesture arena resolves —
              // firing onDragActiveChanged here, not from onPanStart below,
              // is what actually wins the race against the enclosing
              // ListView's own scroll recognizer. See the field doc on
              // DrivePad.onDragActiveChanged.
              onPointerDown: (_) => widget.onDragActiveChanged?.call(true),
              onPointerUp: (_) => widget.onDragActiveChanged?.call(false),
              onPointerCancel: (_) => widget.onDragActiveChanged?.call(false),
              child: GestureDetector(
                // Opaque: this GestureDetector paints nothing of its own, so
                // without it the invisible margin wouldn't accept a touch at
                // all — only the CustomPaint's real pixels would.
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) {
                  _press.forward();
                  widget.onPanStart(d, _Joystick._hitCenter, _Joystick._radius);
                },
                onPanUpdate: (d) => widget.onPanUpdate(
                    d, _Joystick._hitCenter, _Joystick._radius),
                onPanEnd: (d) {
                  _press.reverse();
                  widget.onPanEnd(d);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JoystickPainter extends CustomPainter {
  _JoystickPainter({required this.stick, required this.knobScale});

  final Offset stick;
  final double knobScale;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    canvas.drawCircle(center, radius, Paint()..color = AppColors.surfaceSunken);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AppColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final knobCenter =
        center + Offset(stick.dx * radius * 0.7, stick.dy * radius * 0.7);
    final knobRadius = 26 * knobScale;
    canvas.drawCircle(
        knobCenter, knobRadius, Paint()..color = AppColors.primary);
    canvas.drawCircle(
      knobCenter,
      knobRadius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter oldDelegate) =>
      oldDelegate.stick != stick || oldDelegate.knobScale != knobScale;
}

/// A plain round press-and-hold icon button, used by the two rotate
/// controls. Held inside Teleop's scrollable controls list, same as the
/// joystick — a held tap whose finger drifts even slightly can otherwise
/// lose its TapGestureRecognizer to the ListView's own scroll recognizer
/// and get `onTapCancel`'d mid-hold, which reads as "the button doesn't
/// work" (a held rotate cut short) rather than an outright dead button. See
/// DrivePad.onDragActiveChanged for why this fires from Listener.onPointer*
/// rather than the Tap callbacks.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.size,
    required this.active,
    required this.onStart,
    required this.onEnd,
    this.onDragActiveChanged,
  });

  final IconData icon;
  final double size;
  final bool active;
  final VoidCallback onStart;
  final VoidCallback onEnd;
  final ValueChanged<bool>? onDragActiveChanged;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onDragActiveChanged?.call(true),
      onPointerUp: (_) => onDragActiveChanged?.call(false),
      onPointerCancel: (_) => onDragActiveChanged?.call(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => onStart(),
        onTapUp: (_) => onEnd(),
        onTapCancel: onEnd,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? AppColors.primary : AppColors.surface,
            border: active ? null : Border.all(color: AppColors.border),
          ),
          child: Icon(icon,
              color: active ? AppColors.textOnPrimary : AppColors.textPrimary,
              size: size * 0.5),
        ),
      ),
    );
  }
}
