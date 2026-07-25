import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:nav2_mission_planner/screens/settings/widgets/setting_card.dart';
import 'package:nav2_mission_planner/screens/settings/widgets/setting_header.dart';
import 'package:nav2_mission_planner/screens/settings/widgets/velocity_control.dart';
import 'package:provider/provider.dart';
import '../../constants/default_settings.dart';
import '../../constants/modes.dart';
import '../../providers/settings_provider.dart';
import 'about_settings.dart';

class SettingsContent extends StatelessWidget {
  final String category;
  final Size screenSize;

  const SettingsContent({
    super.key,
    required this.category,
    required this.screenSize,
  });

  Color _modeColor(BuildContext context, String category) {
    if (category == 'Teleop') {
      return ModeColors.getModeColorMap(context)[AppModes.teleop]!;
    }
    return ModeColors.getModeColorMap(context)[AppModes.settings]!;
  }

  @override
  Widget build(BuildContext context) {
    final color = _modeColor(context, category);
    return Column(
      children: [
        const SizedBox(height: 12),
        Expanded(
          child: switch (category) {
            'Robot' => _RobotDefaults(screenSize: screenSize, modeColor: color),
            'Teleop' => _TeleopSpeeds(screenSize: screenSize, modeColor: color),
            'About' => AboutSettings(screenSize: screenSize, modeColor: color),
            _ => const Center(
                child: Text('Select a category',
                    style: TextStyle(color: Colors.white70)),
              ),
          },
        ),
      ],
    );
  }
}

class _RobotDefaults extends StatelessWidget {
  final Size screenSize;
  final Color modeColor;

  const _RobotDefaults({required this.screenSize, required this.modeColor});

  @override
  Widget build(BuildContext context) {
    final rows = <MapEntry<String, String>>[
      const MapEntry('Maps path', DefaultSettings.defaultMapsFolder),
      const MapEntry(
          'Mapping launch', DefaultSettings.defaultMappingLaunchFile),
      const MapEntry(
          'Navigation launch', DefaultSettings.defaultNavigationLaunchFile),
      const MapEntry('cmd_vel', DefaultSettings.cmdVelTopic),
      const MapEntry('Odom', DefaultSettings.defaultOdomTopic),
      const MapEntry('Lidar', DefaultSettings.defaultLidarTopic),
      const MapEntry('Path', DefaultSettings.defaultPathTopic),
      const MapEntry('Map / base',
          '${DefaultSettings.defaultMapFrame} → ${DefaultSettings.defaultBaseLinkFrame}'),
    ];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingHeader(
            title: 'NavProMini defaults',
            icon: FontAwesomeIcons.robot,
            screenSize: screenSize,
            modeColor: modeColor,
          ),
          SizedBox(height: screenSize.height * 0.015),
          SettingCard(
            title: 'Locked for this robot',
            description:
                'Mapping, navigation, and ROS topics are fixed. No setup needed.',
            content: Column(
              children: rows
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 140,
                            child: Text(
                              e.key,
                              style: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              e.value,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          Icon(Icons.lock_outline,
                              size: 14, color: Colors.grey.shade600),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
            modeColor: modeColor,
            screenSize: screenSize,
          ),
        ],
      ),
    );
  }
}

class _TeleopSpeeds extends StatelessWidget {
  final Size screenSize;
  final Color modeColor;

  const _TeleopSpeeds({required this.screenSize, required this.modeColor});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingHeader(
                title: 'Teleop speeds',
                icon: FontAwesomeIcons.gamepad,
                screenSize: screenSize,
                modeColor: modeColor,
              ),
              SizedBox(height: screenSize.height * 0.015),
              SettingCard(
                title: 'cmd_vel (locked)',
                description: DefaultSettings.cmdVelTopic,
                content: const SizedBox.shrink(),
                modeColor: modeColor,
                screenSize: screenSize,
              ),
              SettingCard(
                title: 'Linear velocity',
                description: 'Max linear speed (m/s)',
                content: VelocityControl(
                  value: settings.linearVelocity,
                  onIncrement: settings.incrementLinearVelocity,
                  onDecrement: settings.decrementLinearVelocity,
                  onChanged: (value) {
                    if (value != null) settings.setLinearVelocity(value);
                  },
                  screenSize: screenSize,
                  modeColor: modeColor,
                ),
                modeColor: modeColor,
                screenSize: screenSize,
              ),
              SettingCard(
                title: 'Angular velocity',
                description: 'Max angular speed (rad/s)',
                content: VelocityControl(
                  value: settings.angularVelocity,
                  onIncrement: settings.incrementAngularVelocity,
                  onDecrement: settings.decrementAngularVelocity,
                  onChanged: (value) {
                    if (value != null) settings.setAngularVelocity(value);
                  },
                  screenSize: screenSize,
                  modeColor: modeColor,
                ),
                modeColor: modeColor,
                screenSize: screenSize,
              ),
            ],
          ),
        );
      },
    );
  }
}
