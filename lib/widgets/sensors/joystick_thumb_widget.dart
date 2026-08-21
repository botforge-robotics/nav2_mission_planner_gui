import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/connection_provider.dart';
import 'package:geometry_msgs/msg.dart';
import 'package:ros2_api/ros2_api.dart';
import '../../providers/settings_provider.dart';
import 'package:builtin_interfaces/msg.dart' as builtin_interfaces;
import 'package:std_msgs/msg.dart';

/// Minimum normalized stick delta that counts as a "change".
const double _changeEpsilon = 0.04;

class JoystickThumbWidget extends StatefulWidget {
  final Color modeColor;
  const JoystickThumbWidget({super.key, required this.modeColor});

  @override
  State<JoystickThumbWidget> createState() => _JoystickThumbWidgetState();
}

class _JoystickThumbWidgetState extends State<JoystickThumbWidget> {
  Offset _position = Offset.zero;
  bool _isActive = false;
  bool _isDriving = false;
  dynamic _publisher;
  SettingsProvider? _settingsProvider;
  String? _currentTopic;
  String? _currentType;

  double _lastNormX = 0.0;
  double _lastNormY = 0.0;
  Timer? _publishTimer;
  double _cmdLinear = 0.0;
  double _cmdAngular = 0.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _settingsProvider?.addListener(_onSettingsChanged);
    });
    _setupPublisher();
  }

  void _onSettingsChanged() {
    final settings = context.read<SettingsProvider>();
    if (_currentTopic != settings.cmdVelTopic ||
        _currentType != settings.twistType) {
      _setupPublisher();
    }
  }

  void _setupPublisher() {
    final connection = context.read<ConnectionProvider>();
    final settings = context.read<SettingsProvider>();

    _publisher?.shutdown();
    _publisher = null;

    if (connection.isConnected) {
      _currentTopic = settings.cmdVelTopic;
      _currentType = settings.twistType;

      if (settings.twistType == 'geometry_msgs/msg/TwistStamped') {
        _publisher = Publisher<TwistStamped>(
          name: settings.cmdVelTopic,
          type: TwistStamped().fullType,
          ros2: connection.ros2Client,
        );
      } else {
        _publisher = Publisher<Twist>(
          name: settings.cmdVelTopic,
          type: Twist().fullType,
          ros2: connection.ros2Client,
        );
      }
    }
  }

  void _publishTwist(double linear, double angular) {
    if (_publisher == null) return;

    final twist = Twist(
      linear: Vector3(x: linear, y: 0.0, z: 0.0),
      angular: Vector3(x: 0.0, y: 0.0, z: angular),
    );

    final settings = context.read<SettingsProvider>();
    if (settings.twistType == 'geometry_msgs/msg/TwistStamped') {
      final now = DateTime.now().millisecondsSinceEpoch;
      final stampedTwist = TwistStamped(
        header: Header(
          stamp: builtin_interfaces.Time(
            sec: now ~/ 1000,
            nanosec: (now % 1000) * 1000000,
          ),
          frame_id: 'base_link',
        ),
        twist: twist,
      );
      _publisher!.publish(stampedTwist);
    } else {
      _publisher!.publish(twist);
    }
  }

  void _startDriving(double linear, double angular) {
    _cmdLinear = linear;
    _cmdAngular = angular;
    _isDriving = true;
    _publishTwist(linear, angular);

    // Keep publishing at a fixed rate for as long as the stick is held here —
    // many bases need a continuous cmd_vel stream, not a one-shot message.
    // Release is detected via onPanEnd/onPanCancel, not by a timeout, so
    // holding a steady deflection drives continuously until the user lets go.
    _publishTimer?.cancel();
    _publishTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_isDriving) return;
      _publishTwist(_cmdLinear, _cmdAngular);
    });
  }

  /// Stop cmd_vel but leave the thumb where it is (finger may still be down).
  void _stopDrivingKeepStick() {
    _publishTimer?.cancel();
    _publishTimer = null;
    _isDriving = false;
    _cmdLinear = 0.0;
    _cmdAngular = 0.0;
    _publishTwist(0.0, 0.0);
    if (mounted) setState(() {});
  }

  void _updatePosition(Offset localPosition, Size size) {
    final center = size.center(Offset.zero);
    var newPosition = localPosition - center;
    final maxExtent = size.width / 2.5;

    if (newPosition.distance > maxExtent) {
      newPosition = newPosition * (maxExtent / newPosition.distance);
    }

    final normalizedX = -(newPosition.dx / maxExtent).clamp(-1.0, 1.0);
    final normalizedY = -(newPosition.dy / maxExtent).clamp(-1.0, 1.0);

    final changed = (normalizedX - _lastNormX).abs() > _changeEpsilon ||
        (normalizedY - _lastNormY).abs() > _changeEpsilon;

    setState(() {
      _position = newPosition;
      _isActive = true;
    });

    if (!changed && _isDriving) {
      // Same stick pose — nothing to recompute; the publish timer already
      // keeps re-sending the current command every 100ms while held.
      return;
    }

    if (!changed && !_isDriving) {
      // Held still after auto-stop — stay stopped until stick moves again.
      return;
    }

    _lastNormX = normalizedX;
    _lastNormY = normalizedY;

    final settings = context.read<SettingsProvider>();
    final linear = normalizedY * settings.linearVelocity;
    final angular = normalizedX * settings.angularVelocity;

    // Near-center counts as stop.
    if (math.sqrt(linear * linear + angular * angular) < 0.01) {
      _stopDrivingKeepStick();
      return;
    }

    _startDriving(linear, angular);
  }

  void _stopMovement() {
    _publishTimer?.cancel();
    _publishTimer = null;
    _isDriving = false;
    _lastNormX = 0.0;
    _lastNormY = 0.0;
    _cmdLinear = 0.0;
    _cmdAngular = 0.0;

    setState(() {
      _position = Offset.zero;
      _isActive = false;
    });

    _publishTwist(0.0, 0.0);
  }

  @override
  void dispose() {
    _publishTimer?.cancel();
    _settingsProvider?.removeListener(_onSettingsChanged);
    _publisher?.shutdown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final baseSize = constraints.maxWidth;
        return GestureDetector(
          onPanStart: (details) =>
              _updatePosition(details.localPosition, constraints.biggest),
          onPanUpdate: (details) =>
              _updatePosition(details.localPosition, constraints.biggest),
          onPanEnd: (_) => _stopMovement(),
          onPanCancel: _stopMovement,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.modeColor,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.modeColor.withOpacity(0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                )
              ],
            ),
            child: Stack(
              children: [
                Center(
                  child: Container(
                    width: baseSize * 0.8,
                    height: 1,
                    color: widget.modeColor.withOpacity(0.3),
                  ),
                ),
                Center(
                  child: Container(
                    width: 1,
                    height: baseSize * 0.8,
                    color: widget.modeColor.withOpacity(0.3),
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Icon(
                      Icons.keyboard_arrow_up,
                      color: widget.modeColor.withOpacity(0.5),
                      size: 24,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 10,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: widget.modeColor.withOpacity(0.5),
                      size: 24,
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Icon(
                      Icons.keyboard_arrow_left,
                      color: widget.modeColor.withOpacity(0.5),
                      size: 24,
                    ),
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Icon(
                      Icons.keyboard_arrow_right,
                      color: widget.modeColor.withOpacity(0.5),
                      size: 24,
                    ),
                  ),
                ),
                Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    transform: Matrix4.translationValues(
                      _position.dx,
                      _position.dy,
                      0,
                    ),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _isDriving
                            ? widget.modeColor
                            : (_isActive
                                ? widget.modeColor.withOpacity(0.45)
                                : Colors.white),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                        boxShadow: _isDriving
                            ? [
                                BoxShadow(
                                  color: widget.modeColor.withOpacity(0.6),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                )
                              ]
                            : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
