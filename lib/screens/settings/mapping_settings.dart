import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:nav2_mission_planner/screens/settings/widgets/odom_topic_input.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import 'widgets/setting_card.dart';
import 'widgets/setting_header.dart';
import 'widgets/maps_path_input.dart';
import 'widgets/launch_file_input.dart';
import 'widgets/arguments_list.dart';

class MappingSettings extends StatelessWidget {
  final Size screenSize;
  final Color modeColor;

  const MappingSettings({
    super.key,
    required this.screenSize,
    required this.modeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(builder: (context, settings, child) {
      return SingleChildScrollView(
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          SettingHeader(
            title: 'Mapping Settings',
            icon: FontAwesomeIcons.map,
            screenSize: screenSize,
            modeColor: modeColor,
          ),

          SizedBox(height: screenSize.height * 0.02),
          // Launch File Setting
          SettingCard(
            title: 'Start Mapping Launch File',
            description: 'Set Launch File and Arguments for starting mapping.',
            modeColor: modeColor,
            screenSize: screenSize,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LaunchFileInput(
                  initialValue: settings.mappingLaunchFile,
                  onChanged: settings.setMappingLaunchFile,
                  screenSize: screenSize,
                  modeColor: modeColor,
                  hintText: 'cartographer_ros/cartographer',
                ),
                SizedBox(height: screenSize.height * 0.015),
                // Arguments List (right side)
                ArgumentsList(
                  arguments: settings.mappingArgs,
                  onRemove: (index) =>
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                    settings.removeMappingArg(index);
                  }),
                  onAdd: (key, value) =>
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                    settings.addMappingArg('', '');
                  }),
                  onUpdate: (index, key, value) =>
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                    settings.updateMappingArg(index, key, value);
                  }),
                  screenSize: screenSize,
                  modeColor: modeColor,
                ),
              ],
            ),
          ),
          // Maps Path Setting
          SettingCard(
            title: 'Maps Storage Path',
            description: 'Set the path where maps will be saved',
            modeColor: modeColor,
            screenSize: screenSize,
            content: MapsPathInput(
              initialValue: settings.mapsPath,
              onChanged: settings.setMapsPath,
              screenSize: screenSize,
              modeColor: modeColor,
            ),
          ),
          // Mapping Odom Topic Setting
          SettingCard(
            title: 'Mapping Odom Topic',
            description: 'Set the topic for mapping odom data',
            modeColor: modeColor,
            screenSize: screenSize,
            content: OdomTopicInput(
              initialValue: settings.mappingOdomTopic,
              initialValueType: settings.mappingOdomTopicType,
              onChanged: settings.setMappingOdomTopic,
              screenSize: screenSize,
              modeColor: modeColor,
            ),
          ),
          SizedBox(height: screenSize.height * 0.1),
        ],
      ));
    });
  }
}
