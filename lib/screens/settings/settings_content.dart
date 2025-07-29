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
  Color _getModeColor(BuildContext context, String category) {
    switch (category) {
      case 'Teleop':
        return ModeColors.getModeColorMap(context)[AppModes.teleop]!;
      case 'Mapping':
        return ModeColors.getModeColorMap(context)[AppModes.mapping]!;
      case 'Navigation':
        return ModeColors.getModeColorMap(context)[AppModes.navigation]!;
      case 'General':
        return ModeColors.getModeColorMap(context)[AppModes.settings]!;
      default:
        return ModeColors.getModeColorMap(context)[AppModes.settings]!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: 12),
        Expanded(
          child: _getSettingsContent(context),
        ),
      ],
    );
  }

  Widget _getSettingsContent(BuildContext context) {
    if (category == 'Teleop') {
      return TeleopSettings(
        screenSize: screenSize,
        modeColor: _getModeColor(context, 'Teleop'),
      );
    } else if (category == 'Mapping') {
      return MappingSettings(
        screenSize: screenSize,
        modeColor: _getModeColor(context, 'Mapping'),
      );
    } else if (category == 'Navigation') {
      return NavigationSettings(
        screenSize: screenSize,
        modeColor: _getModeColor(context, 'Navigation'),
      );
    } else if (category == 'General') {
      return GeneralSettings(
        screenSize: screenSize,
        modeColor: _getModeColor(context, 'General'),
      );
    } else if (category == 'About') {
      return AboutSettings(
        screenSize: screenSize,
        modeColor: _getModeColor(context, 'General'),
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
