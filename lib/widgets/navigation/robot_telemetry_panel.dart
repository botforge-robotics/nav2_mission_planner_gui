import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Live numeric readout of where the robot is and what it is being told to do.
///
/// The map view answers "roughly there"; this answers "exactly where", which is
/// what you need when comparing against a waypoint, checking whether odometry
/// has drifted, or confirming the stick is actually reaching the base.
///
/// Deliberately numbers-only. Anything that needed a gauge or a graph belongs
/// in the map itself — this exists precisely because the map cannot tell you
/// that x is 0.970 and not 0.97 something.
class RobotTelemetryPanel extends StatelessWidget {
  final Color modeColor;

  /// Pose in [frame]. Metres and radians.
  final double x;
  final double y;
  final double theta;

  /// Which frame the pose is expressed in — `odom` or `map`.
  ///
  /// Shown rather than assumed: an odom pose is measured from wherever the
  /// robot last started, so comparing one against a saved map coordinate is a
  /// mistake the readout should make visible instead of hiding.
  final String frame;

  /// Measured velocity from wheel odometry, m/s and rad/s.
  final double? measuredLinear;
  final double? measuredAngular;

  /// Last teleop command published, m/s and rad/s. Null when the joystick
  /// is hidden or has never been touched this session.
  final double? commandedLinear;
  final double? commandedAngular;

  /// True while the stick is deflected, so the command row can be dimmed
  /// when it is only showing the trailing zero.
  final bool teleopActive;

  final bool poseAvailable;

  const RobotTelemetryPanel({
    super.key,
    required this.modeColor,
    required this.x,
    required this.y,
    required this.theta,
    required this.frame,
    this.measuredLinear,
    this.measuredAngular,
    this.commandedLinear,
    this.commandedAngular,
    this.teleopActive = false,
    this.poseAvailable = true,
  });

  @override
  Widget build(BuildContext context) {
    final isMap = frame.toLowerCase().contains('map');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(
            'POSITION',
            // Green for map, amber for odom: not decoration. A map pose is
            // comparable to stored waypoints and an odom pose is not, and
            // that difference is worth noticing at a glance — kept as
            // color even though the label itself no longer names the frame.
            isMap ? const Color(0xFF4CAF50) : const Color(0xFFFFB74D),
          ),
          const SizedBox(height: 4),
          if (!poseAvailable)
            _dim('no pose yet')
          else ...[
            _row('X', _metres(x)),
            _row('Y', _metres(y)),
            _row('θ', _radians(theta)),
          ],
          const SizedBox(height: 8),
          _divider(),
          const SizedBox(height: 8),
          _header('VELOCITY', modeColor),
          const SizedBox(height: 4),
          if (measuredLinear == null || measuredAngular == null)
            _dim('not reported')
          else ...[
            _row('v', _speed(measuredLinear!, 'm/s')),
            _row('ω', _speed(measuredAngular!, 'rad/s')),
          ],
          if (commandedLinear != null && commandedAngular != null) ...[
            const SizedBox(height: 8),
            _divider(),
            const SizedBox(height: 8),
            _header(
              'TELEOP',
              teleopActive ? modeColor : Colors.white38,
            ),
            const SizedBox(height: 4),
            _row('v', _speed(commandedLinear!, 'm/s'), dimmed: !teleopActive),
            _row('ω', _speed(commandedAngular!, 'rad/s'),
                dimmed: !teleopActive),
          ],
        ],
      ),
    );
  }

  // -- formatting ----------------------------------------------------------
  //
  // Fixed decimal places and a fixed-width value column, so digits do not
  // jump sideways as the robot drives. A readout that reflows on every
  // update is unreadable in motion, which is the only time it is on screen.

  static String _metres(double v) => '${v.toStringAsFixed(3)} m';

  static String _speed(double v, String unit) =>
      '${v.toStringAsFixed(3)} $unit';

  static String _radians(double rad) {
    // Normalize to (-pi, pi]. Raw yaw can arrive as 6.27 or -0.013 for the
    // same heading depending on the source, and one of those reads as
    // "nearly a full turn away" when it is a fraction of a radian.
    var r = (rad + math.pi) % (2 * math.pi);
    if (r < 0) r += 2 * math.pi;
    r -= math.pi;
    return '${r.toStringAsFixed(3)} rad';
  }

  // -- pieces --------------------------------------------------------------

  Widget _header(String text, Color color) => Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      );

  Widget _row(String label, String value, {bool dimmed = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              child: Text(
                label,
                style: TextStyle(
                  color: dimmed ? Colors.white30 : Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              width: 84,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: dimmed ? Colors.white38 : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _dim(String text) => Text(
        text,
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      );

  Widget _divider() => Container(
        height: 1,
        color: Colors.white.withValues(alpha: 0.10),
      );
}
