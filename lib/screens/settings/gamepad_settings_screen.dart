import 'package:flutter/material.dart';
import 'package:gamepads/gamepads.dart';
import '../../services/gamepad_service.dart';

class GamepadSettingsScreen extends StatefulWidget {
  const GamepadSettingsScreen({super.key});

  @override
  State<GamepadSettingsScreen> createState() => _GamepadSettingsScreenState();
}

class _GamepadSettingsScreenState extends State<GamepadSettingsScreen> {
  final _service = GamepadService.instance;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _service,
      builder: (context, _) {
        final connected = _service.isConnected;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Gamepad Controls'),
            actions: [
              IconButton(
                icon: const Icon(Icons.restore),
                tooltip: 'Reset to Defaults',
                onPressed: () {
                  _service.resetToDefaults();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Gamepad mappings reset to defaults')),
                  );
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Controller Status Card
              Card(
                color: connected ? Colors.green.withValues(alpha: 0.12) : Colors.red.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: connected ? Colors.green.shade400 : Colors.red.shade300,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.sports_esports,
                        size: 36,
                        color: connected ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              connected ? _service.controllerName : 'No Gamepad Detected',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              connected
                                  ? 'Active & Ready for Teleop / Actions'
                                  : 'Connect via Bluetooth or USB to configure & drive',
                              style: TextStyle(
                                fontSize: 13,
                                color: connected ? Colors.green.shade800 : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (connected)
                        const Chip(
                          label: Text('ONLINE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
                          backgroundColor: Colors.white,
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Live Diagnostics / Button Tester
              if (connected) ...[
                const Text(
                  'Live Input Monitor',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('Left Stick (Drive): X=${_service.leftStickX.toStringAsFixed(2)} Y=${_service.leftStickY.toStringAsFixed(2)}'),
                            ),
                            Expanded(
                              child: Text('Right Stick: X=${_service.rightStickX.toStringAsFixed(2)} Y=${_service.rightStickY.toStringAsFixed(2)}'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: _service.pressedButtons.map((btn) {
                            return Chip(
                              label: Text(btn.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              backgroundColor: Colors.blue.shade100,
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Calibration & Speeds
              const Text(
                'Speed & Sensitivity',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Require Deadman Switch (L1 / LB)'),
                        subtitle: const Text('Robot drives only while safety button is held'),
                        value: _service.requireDeadman,
                        onChanged: (val) => _service.setRequireDeadman(val),
                      ),
                      const Divider(),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Invert Forward / Backward Axis'),
                        subtitle: const Text('Reverse stick pitch direction'),
                        value: _service.invertLinear,
                        onChanged: (val) => _service.setInvertLinear(val),
                      ),
                      const Divider(),
                      _buildSliderTile(
                        title: 'Analog Stick Deadzone',
                        subtitle: 'Filter center drift',
                        value: _service.deadzone,
                        min: 0.02,
                        max: 0.35,
                        display: '${(_service.deadzone * 100).toInt()}%',
                        onChanged: (v) => _service.setDeadzone(v),
                      ),
                      const Divider(),
                      _buildSliderTile(
                        title: 'Normal Linear Speed',
                        subtitle: 'Standard driving pace',
                        value: _service.normalLinearSpeed,
                        min: 0.05,
                        max: 0.35,
                        display: '${(_service.normalLinearSpeed * 100).toInt()} cm/s',
                        onChanged: (v) => _service.setNormalLinearSpeed(v),
                      ),
                      const Divider(),
                      _buildSliderTile(
                        title: 'Turbo Linear Speed',
                        subtitle: 'Speed when Turbo (R1 / RB) is held',
                        value: _service.turboLinearSpeed,
                        min: 0.15,
                        max: 0.50,
                        display: '${(_service.turboLinearSpeed * 100).toInt()} cm/s',
                        onChanged: (v) => _service.setTurboLinearSpeed(v),
                      ),
                      const Divider(),
                      _buildSliderTile(
                        title: 'Turn Speed (Angular)',
                        subtitle: 'Rotation rate on steering',
                        value: _service.normalAngularSpeed,
                        min: 0.20,
                        max: 1.00,
                        display: '${_service.normalAngularSpeed.toStringAsFixed(2)} rad/s',
                        onChanged: (v) => _service.setNormalAngularSpeed(v),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Button Remapping
              const Text(
                'Button Mapping',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: GamepadButton.values.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final btn = GamepadButton.values[i];
                    final currentAction = _service.buttonMapping[btn] ?? GamepadAction.none;
                    final isPressed = _service.pressedButtons.contains(btn);

                    return ListTile(
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: isPressed ? Colors.green : Colors.grey.shade200,
                        child: Text(
                          _buttonShortName(btn),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isPressed ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      title: Text(_buttonFullName(btn)),
                      subtitle: Text(
                        currentAction.label,
                        style: TextStyle(
                          color: currentAction != GamepadAction.none ? Colors.blue.shade700 : Colors.grey,
                          fontWeight: currentAction != GamepadAction.none ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () => _showRemapDialog(btn, currentAction),
                    );
                  },
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSliderTile({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text(display, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
          ],
        ),
        Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        Slider(
          value: value,
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }

  void _showRemapDialog(GamepadButton button, GamepadAction current) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Assign ${_buttonFullName(button)}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: GamepadAction.values.map((action) {
                final isSelected = action == current;
                return ListTile(
                  leading: Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: isSelected ? Colors.blue : Colors.grey,
                  ),
                  title: Text(action.label),
                  selected: isSelected,
                  onTap: () {
                    _service.remapButton(button, action);
                    Navigator.pop(ctx);
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  String _buttonShortName(GamepadButton btn) {
    switch (btn) {
      case GamepadButton.a:
        return 'A';
      case GamepadButton.b:
        return 'B';
      case GamepadButton.x:
        return 'X';
      case GamepadButton.y:
        return 'Y';
      case GamepadButton.leftBumper:
        return 'LB';
      case GamepadButton.rightBumper:
        return 'RB';
      case GamepadButton.leftTrigger:
        return 'LT';
      case GamepadButton.rightTrigger:
        return 'RT';
      case GamepadButton.start:
        return 'ST';
      case GamepadButton.back:
        return 'BK';
      case GamepadButton.home:
        return 'HM';
      case GamepadButton.leftStick:
        return 'L3';
      case GamepadButton.rightStick:
        return 'R3';
      case GamepadButton.dpadUp:
        return '▲';
      case GamepadButton.dpadDown:
        return '▼';
      case GamepadButton.dpadLeft:
        return '◀';
      case GamepadButton.dpadRight:
        return '▶';
      case GamepadButton.touchpad:
        return 'TP';
    }
  }

  String _buttonFullName(GamepadButton btn) {
    switch (btn) {
      case GamepadButton.a:
        return 'Button A / Cross';
      case GamepadButton.b:
        return 'Button B / Circle';
      case GamepadButton.x:
        return 'Button X / Square';
      case GamepadButton.y:
        return 'Button Y / Triangle';
      case GamepadButton.leftBumper:
        return 'Left Bumper (LB / L1)';
      case GamepadButton.rightBumper:
        return 'Right Bumper (RB / R1)';
      case GamepadButton.leftTrigger:
        return 'Left Trigger (LT / L2)';
      case GamepadButton.rightTrigger:
        return 'Right Trigger (RT / R2)';
      case GamepadButton.start:
        return 'Start / Menu';
      case GamepadButton.back:
        return 'Back / Select';
      case GamepadButton.home:
        return 'Home / Guide';
      case GamepadButton.leftStick:
        return 'Left Stick Click (L3)';
      case GamepadButton.rightStick:
        return 'Right Stick Click (R3)';
      case GamepadButton.dpadUp:
        return 'D-Pad Up';
      case GamepadButton.dpadDown:
        return 'D-Pad Down';
      case GamepadButton.dpadLeft:
        return 'D-Pad Left';
      case GamepadButton.dpadRight:
        return 'D-Pad Right';
      case GamepadButton.touchpad:
        return 'Touchpad Button';
    }
  }
}
