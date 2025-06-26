import 'package:flutter/material.dart';

enum AppModes { teleop, mapping, navigation, settings }

class ModeColors {
  static const Map<AppModes, Color> modeColorMap = {
    AppModes.teleop: Colors.orange,
    AppModes.mapping: Colors.orange,
    AppModes.navigation: Colors.orange,
    AppModes.settings: Colors.orange,
  };
}
