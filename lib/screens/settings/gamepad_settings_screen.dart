import 'dart:async';
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
  GamepadButton? _selectedButtonForRemap;
  StreamSubscription<GamepadButton>? _buttonPressSub;

  @override
  void initState() {
    super.initState();
    // Safety: In settings screen, block all physical robot commands and motion
    _service.isConfigurationMode = true;
    // Listen for physical button presses: selects the pressed button automatically
    _buttonPressSub = _service.buttonPressEvents.listen((pressedBtn) {
      if (mounted) {
        setState(() {
          _selectedButtonForRemap = pressedBtn;
        });
      }
    });
  }

  @override
  void dispose() {
    _service.isConfigurationMode = false;
    _buttonPressSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _service,
      builder: (context, _) {
        final connected = _service.isConnected;
        final screenWidth = MediaQuery.of(context).size.width;
        final isWideScreen = screenWidth >= 800;

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
                    const SnackBar(content: Text('Gamepad settings reset to defaults')),
                  );
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
                            // Safety Mode Indicator Banner
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade700),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 20, color: Colors.amber.shade900),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Safe Configuration Mode: Physical robot movement and commands are disabled on this screen.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),
              // Controller Status Banner
              Card(
                color: connected
                    ? Colors.green.withValues(alpha: 0.12)
                    : Colors.red.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: connected ? Colors.green.shade400 : Colors.red.shade300,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(
                        Icons.sports_esports,
                        size: 34,
                        color: connected ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              connected ? _service.controllerName : 'No Gamepad Detected',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              connected
                                  ? 'Click a button on the gamepad image or press it on controller to remap'
                                  : 'Connect via Bluetooth or USB to configure & drive',
                              style: TextStyle(
                                fontSize: 12,
                                color: connected ? Colors.green.shade800 : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (connected)
                        const Chip(
                          label: Text('ONLINE',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green)),
                          backgroundColor: Colors.white,
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Visual Gamepad + Action Legend Side-by-Side (or stacked on mobile)
              if (isWideScreen)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: _buildVisualGamepadCard(),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 4,
                      child: _buildActionLegendCard(),
                    ),
                  ],
                )
              else ...[
                _buildVisualGamepadCard(),
                const SizedBox(height: 16),
                _buildActionLegendCard(),
              ],

              const SizedBox(height: 16),

              // Calibration & Speeds
              const Text(
                'Speed & Sensitivity Calibration',
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
                        title: const Text('Require Deadman Switch (LB / L1)'),
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
                        title: 'Normal Linear Speed',
                        subtitle: 'Default pace (Min: 0.07 m/s, Default: 0.10 m/s)',
                        value: _service.normalLinearSpeed,
                        min: 0.07,
                        max: 0.70,
                        display: '${(_service.normalLinearSpeed * 100).toInt()} cm/s (${_service.normalLinearSpeed.toStringAsFixed(2)} m/s)',
                        onChanged: (v) {
                          _service.setNormalLinearSpeed(v);
                          // Auto maintain turbo at 2x if lower
                          if (_service.turboLinearSpeed < v) {
                            _service.setTurboLinearSpeed((v * 2.0).clamp(0.07, 0.70));
                          }
                        },
                      ),
                      const Divider(),
                      _buildSliderTile(
                        title: 'Turbo Linear Speed',
                        subtitle: 'Speed when Turbo (RB / R1) is held (Max: 0.70 m/s)',
                        value: _service.turboLinearSpeed,
                        min: 0.07,
                        max: 0.70,
                        display: '${(_service.turboLinearSpeed * 100).toInt()} cm/s (${_service.turboLinearSpeed.toStringAsFixed(2)} m/s)',
                        onChanged: (v) => _service.setTurboLinearSpeed(v),
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
                        title: 'Turn Speed (Angular)',
                        subtitle: 'Rotation rate on steering',
                        value: _service.normalAngularSpeed,
                        min: 0.15,
                        max: 1.20,
                        display: '${_service.normalAngularSpeed.toStringAsFixed(2)} rad/s',
                        onChanged: (v) => _service.setNormalAngularSpeed(v),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVisualGamepadCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '  Interactive Controller',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                if (_selectedButtonForRemap != null)
                  TextButton.icon(
                    onPressed: () => setState(() => _selectedButtonForRemap = null),
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Deselect', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Center(
              child: SizedBox(
                width: 340,
                height: 315,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Background Gamepad Diagram Image
                    Opacity(
                      opacity: 0.85,
                      child: Image.asset(
                        'assets/gamepad_diagram.png',
                        width: 340,
                        height: 315,
                        fit: BoxFit.contain,
                      ),
                    ),

                    // Interactive Hotspot Targets
                    // Top Triggers & Bumpers
                    _buildHotspot(GamepadButton.leftTrigger, 111, 40, 'LT', isTrigger: true),
                    _buildHotspot(GamepadButton.leftBumper, 107, 65, 'LB'),
                    _buildHotspot(GamepadButton.rightTrigger, 229, 40, 'RT', isTrigger: true),
                    _buildHotspot(GamepadButton.rightBumper, 232, 65, 'RB'),

                    // Center Buttons (Back / Start)
                    _buildHotspot(GamepadButton.back, 145, 131, 'SEL'),
                    _buildHotspot(GamepadButton.start, 197, 131, 'STR'),

                    // D-Pad (Left side)
                    _buildHotspot(GamepadButton.dpadUp, 95, 118, '▲'),
                    _buildHotspot(GamepadButton.dpadDown, 95, 140, '▼'),
                    _buildHotspot(GamepadButton.dpadLeft, 83, 129, '◀'),
                    _buildHotspot(GamepadButton.dpadRight, 107, 129, '▶'),

                    // Face Action Buttons (Right side: X, Y, A, B)
                    _buildHotspot(GamepadButton.y, 245, 118, 'Y'),
                    _buildHotspot(GamepadButton.a, 246, 140, 'A'),
                    _buildHotspot(GamepadButton.x, 234, 129, 'X'),
                    _buildHotspot(GamepadButton.b, 258, 129, 'B'),

                    // Analog Thumbsticks (Clickable L3 / R3)
                    _buildHotspot(GamepadButton.leftStick, 132, 185, 'L3', isStick: true),
                    _buildHotspot(GamepadButton.rightStick, 210, 185, 'R3', isStick: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Selected Button Details & Action Assignment
            _buildSelectedButtonBanner(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionLegendCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.list_alt_rounded, size: 20, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                const Text(
                  'Assigned Actions Legend',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: GamepadButton.values.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final btn = GamepadButton.values[i];
                final action = _service.buttonMapping[btn] ?? GamepadAction.none;
                final isSelected = _selectedButtonForRemap == btn;
                final isPressed = _service.pressedButtons.contains(btn);

                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  leading: CircleAvatar(
                    radius: 13,
                    backgroundColor: isPressed
                        ? Colors.green
                        : (isSelected ? Colors.blue : (action != GamepadAction.none ? Colors.blue.shade50 : Colors.grey.shade200)),
                    child: Text(
                      _buttonShortName(btn),
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: isPressed || isSelected ? Colors.white : (action != GamepadAction.none ? Colors.blue.shade900 : Colors.black87),
                      ),
                    ),
                  ),
                  title: Text(
                    _buttonFullName(btn),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: action != GamepadAction.none ? Colors.blue.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: action != GamepadAction.none ? Colors.blue.shade300 : Colors.grey.shade300,
                      ),
                    ),
                    child: Text(
                      action.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: action != GamepadAction.none ? FontWeight.bold : FontWeight.normal,
                        color: action != GamepadAction.none ? Colors.blue.shade800 : Colors.grey.shade600,
                      ),
                    ),
                  ),
                  onTap: () {
                    setState(() {
                      _selectedButtonForRemap = btn;
                    });
                    _showRemapDialog(btn, action);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHotspot(
    GamepadButton button,
    double x,
    double y,
    String label, {
    bool isTrigger = false,
    bool isStick = false,
  }) {
    final isSelected = _selectedButtonForRemap == button;
    final isPressed = _service.pressedButtons.contains(button);
    final action = _service.buttonMapping[button] ?? GamepadAction.none;
    final hasAction = action != GamepadAction.none;

    Color bg;
    if (isPressed) {
      bg = Colors.green;
    } else if (isSelected) {
      bg = Colors.blue.shade600;
    } else if (hasAction) {
      bg = Colors.blue.shade100;
    } else {
      bg = Colors.grey.shade200;
    }

    Color textCol;
    if (isPressed || isSelected) {
      textCol = Colors.white;
    } else if (hasAction) {
      textCol = Colors.blue.shade900;
    } else {
      textCol = Colors.black87;
    }

    final double width = isStick ? 36 : (isTrigger ? 32 : 26);
    final double height = isStick ? 36 : (isTrigger ? 22 : 22);

    return Positioned(
      left: x - (width / 2),
      top: y - (height / 2),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedButtonForRemap = button;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(isStick ? 20 : (isTrigger ? 6 : 12)),
            border: Border.all(
              color: isSelected
                  ? Colors.blue.shade800
                  : (isPressed ? Colors.green.shade800 : Colors.black45),
              width: isSelected || isPressed ? 2.2 : 1.2,
            ),
            boxShadow: isSelected || isPressed
                ? [
                    BoxShadow(
                      color: (isPressed ? Colors.green : Colors.blue).withValues(alpha: 0.4),
                      blurRadius: 6,
                      spreadRadius: 2,
                    )
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: isStick ? 11 : 9.5,
                fontWeight: FontWeight.bold,
                color: textCol,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedButtonBanner() {
    final btn = _selectedButtonForRemap;
    if (btn == null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Row(
          children: [
            Icon(Icons.touch_app, size: 20, color: Colors.blue),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tap any button above or press it physically to assign its action.',
                style: TextStyle(fontSize: 12.5, color: Colors.black87),
              ),
            ),
          ],
        ),
      );
    }

    final currentAction = _service.buttonMapping[btn] ?? GamepadAction.none;
    final isPressed = _service.pressedButtons.contains(btn);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isPressed ? Colors.green.withValues(alpha: 0.12) : Colors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPressed ? Colors.green : Colors.blue.shade400,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: isPressed ? Colors.green : Colors.blue,
                child: Text(
                  _buttonShortName(btn),
                  style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _buttonFullName(btn),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    Text(
                      'Action: ${currentAction.label}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: currentAction != GamepadAction.none ? Colors.blue.shade800 : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showRemapDialog(btn, currentAction),
                icon: const Icon(Icons.edit, size: 14),
                label: const Text('Change Action', style: TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
            ],
          ),
          if (isPressed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 14, color: Colors.green),
                  const SizedBox(width: 4),
                  Text(
                    'Physically pressed on controller right now',
                    style: TextStyle(fontSize: 11, color: Colors.green.shade800, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
        ],
      ),
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
