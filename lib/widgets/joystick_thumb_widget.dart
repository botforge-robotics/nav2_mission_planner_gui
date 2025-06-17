import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/connection_provider.dart';
import 'package:geometry_msgs/msg.dart';
import 'package:ros2_api/ros2_api.dart';
import '../providers/settings_provider.dart';
import 'package:builtin_interfaces/msg.dart' as builtin_interfaces;
import 'package:std_msgs/msg.dart';

class JoystickThumbWidget extends StatefulWidget {
  final Color modeColor;
  const JoystickThumbWidget({super.key, required this.modeColor});

  @override
  State<JoystickThumbWidget> createState() => _JoystickThumbWidgetState();
}

class _JoystickThumbWidgetState extends State<JoystickThumbWidget> {
  Offset _position = Offset.zero;
  bool _isActive = false;
  dynamic _publisher;
  SettingsProvider? _settingsProvider;
  String? _currentTopic;
  String? _currentType;

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

    // Shutdown existing publisher if it exists
    _publisher?.shutdown();
    _publisher = null;

    if (connection.ros2Client != null && connection.isConnected) {
      _currentTopic = settings.cmdVelTopic;
      _currentType = settings.twistType;

      if (settings.twistType == 'geometry_msgs/msg/TwistStamped') {
        _publisher = Publisher<TwistStamped>(
          name: settings.cmdVelTopic,
          type: TwistStamped().fullType,
          ros2: connection.ros2Client!,
        );
      } else {
        _publisher = Publisher<Twist>(
          name: settings.cmdVelTopic,
          type: Twist().fullType,
          ros2: connection.ros2Client!,
        );
      }
    }
  }

  void _updatePosition(Offset localPosition, Size size) {
    final center = size.center(Offset.zero);
    var newPosition = localPosition - center;
    final maxExtent = size.width / 2.5;

    // Limit to circular bounds
    if (newPosition.distance > maxExtent) {
      newPosition = newPosition * (maxExtent / newPosition.distance);
    }

    setState(() {
      _position = newPosition;
      _isActive = true;
    });

    // Normalize values between -1 and 1
    final normalizedX = -(newPosition.dx / maxExtent).clamp(-1.0, 1.0);
    final normalizedY = -(newPosition.dy / maxExtent).clamp(-1.0, 1.0);

    final settings = context.read<SettingsProvider>();
    final linear = normalizedY * settings.linearVelocity;
    final angular = normalizedX * settings.angularVelocity;

    // Create velocity message
    if (_publisher != null) {
      final twist = Twist(
        linear: Vector3(x: linear, y: 0.0, z: 0.0),
        angular: Vector3(x: 0.0, y: 0.0, z: angular),
      );

      // Publish based on message type
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
  }

  void _stopMovement() {
    setState(() {
      _position = Offset.zero;
      _isActive = false;
    });

    // Send zero velocity
    if (_publisher != null) {
      final twist = Twist(
        linear: Vector3(x: 0.0, y: 0.0, z: 0.0),
        angular: Vector3(x: 0.0, y: 0.0, z: 0.0),
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
  }

  @override
  void dispose() {
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
                // Crosshair guides
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

                // Direction markers
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

                // Thumb control
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
                        color: _isActive ? widget.modeColor : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                        boxShadow: _isActive
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
