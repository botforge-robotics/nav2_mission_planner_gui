import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import 'widgets/camera_topic_input.dart';
import 'widgets/setting_card.dart';
import 'widgets/setting_header.dart';
import 'widgets/lidar_topic_input.dart';
import 'widgets/communication_timeout_input.dart';
import 'widgets/tf_topic_dropdown.dart';

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
                  title: 'TF Topic',
                  description: 'Set topic for TF transforms',
                  modeColor: modeColor,
                  screenSize: screenSize,
                  content: Column(
                    children: [
                      TFTopicDropdown(
                        initialValue: settings.tfTopic,
                        onChanged: settings.setTfTopic,
                        modeColor: modeColor,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.grey[900],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: modeColor.withOpacity(0.5),
                                  width: 1,
                                ),
                              ),
                              child: TextFormField(
                                initialValue: settings.mapFrame,
                                style: TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: 'Map Frame',
                                  labelStyle:
                                      TextStyle(color: Colors.grey.shade400),
                                  hintText: 'map',
                                  hintStyle:
                                      TextStyle(color: Colors.grey.shade500),
                                  filled: true,
                                  fillColor: Colors.transparent,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                ),
                                onChanged: settings.setMapFrame,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.grey[900],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: modeColor.withOpacity(0.5),
                                  width: 1,
                                ),
                              ),
                              child: TextFormField(
                                initialValue: settings.odomFrame,
                                style: TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: 'Odom Frame',
                                  labelStyle:
                                      TextStyle(color: Colors.grey.shade400),
                                  hintText: 'odom',
                                  hintStyle:
                                      TextStyle(color: Colors.grey.shade500),
                                  filled: true,
                                  fillColor: Colors.transparent,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                ),
                                onChanged: settings.setOdomFrame,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.grey[900],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: modeColor.withOpacity(0.5),
                                  width: 1,
                                ),
                              ),
                              child: TextFormField(
                                initialValue: settings.baseLinkFrame,
                                style: TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: 'Base Link Frame',
                                  labelStyle:
                                      TextStyle(color: Colors.grey.shade400),
                                  hintText: 'base_link',
                                  hintStyle:
                                      TextStyle(color: Colors.grey.shade500),
                                  filled: true,
                                  fillColor: Colors.transparent,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                ),
                                onChanged: settings.setBaseLinkFrame,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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
                SettingCard(
                  title: 'Communication Timeout',
                  description:
                      'Maximum time without robot messages before connection is considered lost (seconds)',
                  modeColor: modeColor,
                  screenSize: screenSize,
                  content: CommunicationTimeoutInput(
                    initialValue: settings.communicationTimeout,
                    onChanged: settings.setCommunicationTimeout,
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
