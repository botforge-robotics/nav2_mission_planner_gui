import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import 'widgets/camera_topic_input.dart';
import 'widgets/setting_card.dart';
import 'widgets/setting_header.dart';
import 'widgets/odom_topic_input.dart';
import 'widgets/lidar_topic_input.dart';

class GeneralSettings extends StatelessWidget {
  final Size screenSize;
  final Color modeColor;

  const GeneralSettings({
    super.key,
    required this.screenSize,
    required this.modeColor,
  });

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingHeader(
            title: 'Sensor Settings',
            icon: FontAwesomeIcons.gear,
            screenSize: screenSize,
            modeColor: modeColor,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                SettingCard(
                  title: 'Camera Image Topic',
                  description: 'Set topic for compressed image stream',
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
                  title: 'Odometry Topic',
                  description: 'Set topic for odometry data',
                  modeColor: modeColor,
                  screenSize: screenSize,
                  content: OdomTopicInput(
                    initialValue: settings.odomTopic,
                    initialValueType: settings.odomTopicType,
                    onChanged: settings.setOdomTopic,
                    screenSize: screenSize,
                    modeColor: modeColor,
                  ),
                ),
                SettingCard(
                  title: 'Lidar Topic',
                  description: 'Set topic for lidar scan data',
                  modeColor: modeColor,
                  screenSize: screenSize,
                  content: LidarTopicInput(
                    initialValue: settings.lidarTopic,
                    onChanged: settings.setLidarTopic,
                    screenSize: screenSize,
                    modeColor: modeColor,
                  ),
                ),
                SizedBox(height: screenSize.height * 0.1),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
