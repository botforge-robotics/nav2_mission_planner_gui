import 'package:flutter/material.dart';
import '../../constants/modes.dart';
import 'teleop_settings.dart';
import 'mapping_settings.dart';
import 'navigation_settings.dart';
import 'general_settings.dart';
import 'about_settings.dart';

class SettingsContent extends StatelessWidget {
  final String category;
  final Size screenSize;

  const SettingsContent({
    super.key,
    required this.category,
    required this.screenSize,
  });

  // Helper method to get color from mode
  Color _getModeColor(String category) {
    switch (category) {
      case 'Teleop':
        return ModeColors.modeColorMap[AppModes.teleop]!;
      case 'Mapping':
        return ModeColors.modeColorMap[AppModes.mapping]!;
      case 'Navigation':
        return ModeColors.modeColorMap[AppModes.navigation]!;
      case 'General':
        return ModeColors.modeColorMap[AppModes.settings]!;
      default:
        return ModeColors.modeColorMap[AppModes.settings]!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: 12),
        Expanded(
          child: _getSettingsContent(),
        ),
      ],
    );
  }

  Widget _getSettingsContent() {
    if (category == 'Teleop') {
      return TeleopSettings(
        screenSize: screenSize,
        modeColor: _getModeColor('Teleop'),
      );
    } else if (category == 'Mapping') {
      return MappingSettings(
        screenSize: screenSize,
        modeColor: _getModeColor('Mapping'),
      );
    } else if (category == 'Navigation') {
      return NavigationSettings(
        screenSize: screenSize,
        modeColor: _getModeColor('Navigation'),
      );
    } else if (category == 'General') {
      return GeneralSettings(
        screenSize: screenSize,
        modeColor: _getModeColor('General'),
      );
    } else if (category == 'About') {
      return AboutSettings(
        screenSize: screenSize,
        modeColor: _getModeColor('General'),
      );
    }
    return Center(
      child: Text(
        '$category Settings Coming Soon',
        style: TextStyle(fontSize: screenSize.height * 0.04),
      ),
    );
  }
}
