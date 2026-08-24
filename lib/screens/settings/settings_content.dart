import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:nav2_mission_planner/screens/settings/widgets/setting_card.dart';
import 'package:nav2_mission_planner/screens/settings/widgets/setting_header.dart';
import 'package:nav2_mission_planner/screens/settings/widgets/velocity_control.dart';
import 'package:nav2_mission_planner/screens/settings/widgets/camera_topic_input.dart';
import 'package:nav2_mission_planner/screens/settings/widgets/communication_timeout_input.dart';
import 'package:provider/provider.dart';
import '../../constants/default_settings.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_spacing.dart';
import 'about_settings.dart';

class SettingsContent extends StatelessWidget {
  final String category;
  final Size screenSize;

  const SettingsContent({
    super.key,
    required this.category,
    required this.screenSize,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: switch (category) {
            'Robot' => _RobotDefaults(screenSize: screenSize, modeColor: color),
            'Teleop' => _TeleopSpeeds(screenSize: screenSize, modeColor: color),
            'Sensor' => _SensorSettings(screenSize: screenSize, modeColor: color),
            'About' => AboutSettings(screenSize: screenSize, modeColor: color),
            _ => Center(
                child: Text('Select a category',
                    style: Theme.of(context).textTheme.bodyMedium),
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
    final theme = Theme.of(context);
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
          const SizedBox(height: AppSpacing.md),
          SettingCard(
            title: 'Locked for this robot',
            description:
                'Mapping, navigation, and ROS topics are fixed. No setup needed.',
            content: Column(
              children: rows
                  .map(
                    (e) => Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 140,
                            child: Text(
                              e.key,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              e.value,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                          Icon(Icons.lock_outline,
                              size: 14, color: theme.colorScheme.outline),
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
              const SizedBox(height: AppSpacing.md),
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

/// Camera + comms-timeout — the only sensor-adjacent settings that are
/// actually per-install preferences rather than part of the NavProMini
/// locked contract (topics/frames/launch files stay in `_RobotDefaults`,
/// read-only, per CLAUDE.md). Deliberately does NOT reuse the old
/// `general_settings.dart` wholesale — that file also exposes raw
/// map/odom/base_link frame and TF/lidar topic editors, which would let a
/// client drift exactly the fixed contract fields the server is meant to
/// lock down.
class _SensorSettings extends StatelessWidget {
  final Size screenSize;
  final Color modeColor;

  const _SensorSettings({required this.screenSize, required this.modeColor});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingHeader(
                title: 'Sensor',
                icon: FontAwesomeIcons.camera,
                screenSize: screenSize,
                modeColor: modeColor,
              ),
              const SizedBox(height: AppSpacing.md),
              SettingCard(
                title: 'Camera',
                description: 'Optional — off unless this robot has a camera',
                modeColor: modeColor,
                screenSize: screenSize,
                content: CameraTopicInput(
                  initialValue: settings.cameraImageTopic,
                  onChanged: settings.setCameraImageTopic,
                  screenSize: screenSize,
                  modeColor: modeColor,
                  enabled: settings.cameraEnabled,
                  onEnabledChanged: settings.setCameraEnabled,
                ),
              ),
              SettingCard(
                title: 'Communication timeout',
                description:
                    'Max time without robot messages before the connection is considered lost',
                modeColor: modeColor,
                screenSize: screenSize,
                content: CommunicationTimeoutInput(
                  initialValue: settings.communicationTimeout,
                  onChanged: settings.setCommunicationTimeout,
                  screenSize: screenSize,
                  modeColor: modeColor,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
