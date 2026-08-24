import 'package:flutter/material.dart';
import 'package:nav2_mission_planner/widgets/sensors/joystick_thumb_widget.dart';

/// Bottom-right teleop joystick overlay. Extracted verbatim from
/// navigation_screen.dart's build() — pure render + the same `onCommand`
/// callback the screen already owned; the screen still decides what to do
/// with each command (update its local `_cmdLinear`/`_cmdAngular`/
/// `_teleopActive` state and report it to `LiveTelemetryProvider`), passed
/// straight through here unchanged.
class JoystickOverlay extends StatelessWidget {
  final bool visible;
  final Color modeColor;
  final void Function(double linear, double angular) onCommand;

  const JoystickOverlay({
    super.key,
    required this.visible,
    required this.modeColor,
    required this.onCommand,
  });

  @override
  Widget build(BuildContext context) {
    return Visibility(
      visible: visible,
      child: Positioned(
        bottom: 30,
        right: 40,
        child: Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          child: JoystickThumbWidget(
            modeColor: modeColor,
            onCommand: onCommand,
          ),
        ),
      ),
    );
  }
}
