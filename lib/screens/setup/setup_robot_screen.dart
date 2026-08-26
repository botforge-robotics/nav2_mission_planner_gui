import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/setup_flow_controller.dart';
import '../../services/robot_connection_store.dart';
import '../../services/rosbridge_probe.dart';
import '../../theme/app_theme.dart';
import 'setup_complete_screen.dart';
import 'setup_scaffold.dart';

/// Opens the actual rosbridge WebSocket via ros2_api's Ros2 client (through
/// probeRosbridge — the same helper Splash uses for its silent reconnect
/// check) — the same vendored connection layer the rest of the app will
/// use, not a separate one built just for setup. The connection is closed
/// again once confirmed; a full app owning a persistent connection is the
/// job of the future ConnectionProvider rebuild, not this flow.
class SetupRobotScreen extends StatefulWidget {
  const SetupRobotScreen({super.key});

  @override
  State<SetupRobotScreen> createState() => _SetupRobotScreenState();
}

class _SetupRobotScreenState extends State<SetupRobotScreen> {
  String? _error;
  bool _connecting = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  Future<void> _connect() async {
    final robot = context.read<SetupFlowController>().selectedRobot;
    if (robot == null) {
      setState(() {
        _error = 'No robot selected.';
        _connecting = false;
      });
      return;
    }

    setState(() {
      _connecting = true;
      _error = null;
    });

    final ok = await probeRosbridge(robot.rosbridgeUrl);
    if (!mounted) return;

    if (ok) {
      await RobotConnectionStore()
          .save(SavedRobot(name: robot.name, ip: robot.ip));
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SetupCompleteScreen()),
      );
    } else {
      setState(() {
        _error = 'Could not connect to ${robot.name}. Make sure it\'s still on '
            'the same network and try again.';
        _connecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final robot = context.watch<SetupFlowController>().selectedRobot;
    return SetupScaffold(
      step: 3,
      totalSteps: 4,
      title: 'Robot Connection',
      subtitle:
          _connecting && robot != null ? 'Connecting to ${robot.name}…' : null,
      primaryLabel: _error != null ? 'Retry' : null,
      onPrimary: _error != null ? _connect : null,
      child: Center(
        child: _error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_tethering_error_rounded,
                      size: 48, color: AppColors.danger),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
