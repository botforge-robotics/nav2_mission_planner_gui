import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gamepads/gamepads.dart';
import '../../services/gamepad_service.dart';
import '../../theme/app_theme.dart';

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
    final colors = AppColors.of(context);

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
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, size: 20, color: AppColors.warning),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Safe Configuration Mode: Physical robot movement and commands are disabled on this screen.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              // Controller Status Banner
              Card(
                color: connected
                    ? AppColors.success.withValues(alpha: 0.1)
                    : colors.surfaceSunken,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: connected ? AppColors.success.withValues(alpha: 0.4) : colors.border,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(
                        Icons.sports_esports_rounded,
                        size: 34,
                        color: connected ? AppColors.success : colors.textSecondary,
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
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (connected)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.success),
                          ),
                          child: const Text(
                            'ONLINE',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.success),
                          ),
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
                      child: _buildVisualGamepadCard(colors),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 4,
                      child: _buildActionLegendCard(colors),
                    ),
                  ],
                )
              else ...[
                _buildVisualGamepadCard(colors),
                const SizedBox(height: 16),
                _buildActionLegendCard(colors),
              ],

              const SizedBox(height: 16),

              // Calibration & Speeds
              Text(
                'Speed & Sensitivity Calibration',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colors.textSecondary),
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
                        colors: colors,
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
                        colors: colors,
                        title: 'Turbo Linear Speed',
                        subtitle: 'Speed when Turbo (RB / R1) is held (Max: 0.70 m/s)',
                        value: _service.turboLinearSpeed,
                        min: 0.07,
                        max: 0.70,
                        display: '${(_service.turboLinearSpeed * 100).toInt()} cm/s (${_service.turboLinearSpeed.toStringAsFixed(2)} m/s)',
                        onChanged: (v) => _service.setTurboLinearSpeed(v),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVisualGamepadCard(AppColorsTheme colors) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.gamepad_rounded, size: 20, color: colors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Interactive Controller Map',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: SizedBox(
                width: 340,
                height: 250,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Image.asset(
                        'assets/gamepad_blueprint.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Center(
                          child: Icon(Icons.videogame_asset_rounded, size: 100, color: colors.textSecondary),
                        ),
                      ),
                    ),

                    // Left Shoulder & Triggers
                    _buildHotspot(colors, GamepadButton.leftTrigger, 111, 40, 'LT', isTrigger: true),
                    _buildHotspot(colors, GamepadButton.leftBumper, 108, 65, 'LB'),

                    // Right Shoulder & Triggers
                    _buildHotspot(colors, GamepadButton.rightTrigger, 229, 40, 'RT', isTrigger: true),
                    _buildHotspot(colors, GamepadButton.rightBumper, 232, 65, 'RB'),

                    // Center Buttons (Back / Start)
                    _buildHotspot(colors, GamepadButton.back, 145, 131, 'SEL'),
                    _buildHotspot(colors, GamepadButton.start, 197, 131, 'STR'),

                    // D-Pad (Left side)
                    _buildHotspot(colors, GamepadButton.dpadUp, 95, 118, '▲'),
                    _buildHotspot(colors, GamepadButton.dpadDown, 95, 140, '▼'),
                    _buildHotspot(colors, GamepadButton.dpadLeft, 83, 129, '◀'),
                    _buildHotspot(colors, GamepadButton.dpadRight, 107, 129, '▶'),

                    // Face Action Buttons (Right side: X, Y, A, B)
                    _buildHotspot(colors, GamepadButton.y, 245, 118, 'Y'),
                    _buildHotspot(colors, GamepadButton.a, 246, 140, 'A'),
                    _buildHotspot(colors, GamepadButton.x, 234, 129, 'X'),
                    _buildHotspot(colors, GamepadButton.b, 258, 129, 'B'),

                    // Analog Thumbsticks (Clickable L3 / R3)
                    _buildHotspot(colors, GamepadButton.leftStick, 132, 185, 'L3', isStick: true),
                    _buildHotspot(colors, GamepadButton.rightStick, 210, 185, 'R3', isStick: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Selected Button Details & Action Assignment
            _buildSelectedButtonBanner(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildActionLegendCard(AppColorsTheme colors) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.list_alt_rounded, size: 20, color: colors.primary),
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
                        ? AppColors.success
                        : (isSelected
                            ? colors.primary
                            : (action != GamepadAction.none ? colors.primary.withValues(alpha: 0.15) : colors.surfaceSunken)),
                    child: Text(
                      _buttonShortName(btn),
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: isPressed || isSelected
                            ? Colors.white
                            : (action != GamepadAction.none ? colors.primary : colors.textSecondary),
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
                      color: action != GamepadAction.none ? colors.primary.withValues(alpha: 0.1) : colors.surfaceSunken,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: action != GamepadAction.none ? colors.primary.withValues(alpha: 0.3) : colors.border,
                      ),
                    ),
                    child: Text(
                      action.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: action != GamepadAction.none ? FontWeight.bold : FontWeight.normal,
                        color: action != GamepadAction.none ? colors.primary : colors.textSecondary,
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
    AppColorsTheme colors,
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
      bg = AppColors.success;
    } else if (isSelected) {
      bg = colors.primary;
    } else if (hasAction) {
      bg = colors.primary.withValues(alpha: 0.2);
    } else {
      bg = colors.surfaceSunken;
    }

    Color textCol;
    if (isPressed || isSelected) {
      textCol = Colors.white;
    } else if (hasAction) {
      textCol = colors.primary;
    } else {
      textCol = colors.textPrimary;
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
                  ? colors.primary
                  : (isPressed ? AppColors.success : colors.border),
              width: isSelected || isPressed ? 2.2 : 1.2,
            ),
            boxShadow: isSelected || isPressed
                ? [
                    BoxShadow(
                      color: (isPressed ? AppColors.success : colors.primary).withValues(alpha: 0.4),
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

  Widget _buildSelectedButtonBanner(AppColorsTheme colors) {
    final btn = _selectedButtonForRemap;
    if (btn == null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: colors.surfaceSunken,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.touch_app_rounded, size: 20, color: colors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tap any button above or press it physically to assign its action.',
                style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
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
        color: isPressed ? AppColors.success.withValues(alpha: 0.12) : colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPressed ? AppColors.success : colors.primary.withValues(alpha: 0.4),
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
                backgroundColor: isPressed ? AppColors.success : colors.primary,
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
                        color: currentAction != GamepadAction.none ? colors.primary : colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => _showRemapDialog(btn, currentAction),
                icon: const Icon(Icons.edit, size: 14),
                label: const Text('Change Action', style: TextStyle(fontSize: 11)),
                style: FilledButton.styleFrom(
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
                  const Icon(Icons.check_circle, size: 14, color: AppColors.success),
                  const SizedBox(width: 4),
                  Text(
                    'Physically pressed on controller right now',
                    style: TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSliderTile({
    required AppColorsTheme colors,
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
            Text(display, style: TextStyle(fontWeight: FontWeight.bold, color: colors.primary)),
          ],
        ),
        Text(subtitle, style: TextStyle(fontSize: 12, color: colors.textSecondary)),
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
        final colors = AppColors.of(ctx);
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
                    color: isSelected ? colors.primary : colors.textSecondary,
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
