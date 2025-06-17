import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:nav2_mission_planner/screens/settings/widgets/odom_topic_input.dart';
import 'package:nav2_mission_planner/screens/settings/widgets/path_input.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import 'widgets/setting_card.dart';
import 'widgets/setting_header.dart';
import 'widgets/launch_file_input.dart';
import 'widgets/arguments_list.dart';

class NavigationSettings extends StatelessWidget {
  final Size screenSize;
  final Color modeColor;

  const NavigationSettings({
    super.key,
    required this.screenSize,
    required this.modeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(builder: (context, settings, child) {
      return SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          SettingHeader(
            title: 'Navigation Settings',
            icon: FontAwesomeIcons.route,
            screenSize: screenSize,
            modeColor: modeColor,
          ),

          SizedBox(height: screenSize.height * 0.02),

          SettingCard(
            title: 'Navigation Launch File',
            description: 'Set the launch file for navigation',
            modeColor: modeColor,
            screenSize: screenSize,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LaunchFileInput(
                  initialValue: settings.navigationLaunchFile,
                  onChanged: settings.setNavigationLaunchFile,
                  screenSize: screenSize,
                  modeColor: modeColor,
                  hintText: 'nav2_bringup/navigation',
                ),
                SizedBox(height: screenSize.height * 0.02),
                ArgumentsList(
                  arguments: settings.navigationArgs,
                  onRemove: (index) =>
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                    settings.removeNavigationArg(index);
                  }),
                  onAdd: (key, value) =>
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                    settings.addNavigationArg('', '');
                  }),
                  onUpdate: (index, key, value) =>
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                    settings.updateNavigationArg(index, key, value);
                  }),
                  screenSize: screenSize,
                  modeColor: modeColor,
                ),
                Text(
                  'Note: The name of map file will be asked when starting navigation. Please make sure the argument name "map" is correct in your launch file.',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.orange.shade300,
                  ),
                ),
              ],
            ),
          ),
          // Navigation Odom Topic Setting
          SettingCard(
            title: 'Navigation Odom Topic',
            description: 'Set the topic for navigation odom data',
            modeColor: modeColor,
            screenSize: screenSize,
            content: OdomTopicInput(
              initialValue: settings.navigationOdomTopic,
              initialValueType: settings.navigationOdomTopicType,
              onChanged: settings.setNavigationOdomTopic,
              screenSize: screenSize,
              modeColor: modeColor,
            ),
          ),
          // Navigation Path Topic Setting
          SettingCard(
            title: 'Navigation Path Topic',
            description: 'Set the topic for navigation path visualization',
            modeColor: modeColor,
            screenSize: screenSize,
            content: PathTopicInput(
              initialValue: settings.pathTopic,
              onChanged: settings.setPathTopic,
              screenSize: screenSize,
              modeColor: modeColor,
            ),
          ),
          SizedBox(height: screenSize.height * 0.1),
        ]),
      );
    });
  }
}
