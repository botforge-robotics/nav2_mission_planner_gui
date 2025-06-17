import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:nav2_mission_planner/screens/settings/widgets/setting_card.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../constants/default_settings.dart';
import 'widgets/setting_header.dart';
import 'widgets/velocity_control.dart';

class TeleopSettings extends StatelessWidget {
  final Size screenSize;
  final Color modeColor;

  const TeleopSettings({
    super.key,
    required this.screenSize,
    required this.modeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingHeader(
                title: 'Teleop Settings',
                icon: FontAwesomeIcons.gamepad,
                screenSize: screenSize,
                modeColor: modeColor,
              ),
              SizedBox(height: screenSize.height * 0.02),
              SettingCard(
                title: 'CMD_VEL Topic',
                description: 'Set the topic name for velocity commands',
                content: _buildTopicInput(settings),
                modeColor: modeColor,
                screenSize: screenSize,
              ),
              _buildSettingRow(
                title: 'Linear Velocity',
                description: 'Set maximum linear velocity (m/s)',
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
              ),
              _buildSettingRow(
                title: 'Angular Velocity',
                description: 'Set maximum angular velocity (rad/s)',
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
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSettingRow({
    required String title,
    required String description,
    required Widget content,
  }) {
    return Container(
      padding: EdgeInsets.all(screenSize.width * 0.02),
      margin: EdgeInsets.only(bottom: screenSize.height * 0.01),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: modeColor.withOpacity(0.3), width: 2),
      ),
      child: Row(
        children: [
          // Left side - Title and Description
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: modeColor,
                  ),
                ),
                SizedBox(height: screenSize.height * 0.01),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          // Right side - Content
          Expanded(
            flex: 3,
            child: content,
          ),
        ],
      ),
    );
  }

  Widget _buildTopicInput(SettingsProvider settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          initialValue: settings.cmdVelTopic,
          style: TextStyle(fontSize: 12),
          decoration: InputDecoration(
            hintText: 'Enter topic name (e.g. cmd_vel)',
            hintStyle: TextStyle(color: Colors.grey.shade700),
            border: UnderlineInputBorder(
              borderSide: BorderSide(color: modeColor),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: modeColor, width: 2),
            ),
          ),
          onChanged: settings.setCmdVelTopic,
        ),
        SizedBox(height: screenSize.height * 0.03),
        Text(
          'Topic Type:',
          textAlign: TextAlign.left,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey.shade400,
            fontStyle: FontStyle.italic,
          ),
        ),
        SizedBox(height: screenSize.height * 0.01),
        Builder(
          builder: (context) => Container(
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: modeColor.withOpacity(0.5),
                width: 1,
              ),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(
                inputDecorationTheme: InputDecorationTheme(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: ButtonTheme(
                  alignedDropdown: true,
                  child: DropdownButton<String>(
                    value: settings.twistType,
                    items:
                        DefaultSettings.availableTwistTypes.map((String type) {
                      return DropdownMenuItem<String>(
                        value: type,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              type,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        settings.setTwistType(newValue);
                      }
                    },
                    isExpanded: true,
                    icon: Icon(Icons.arrow_drop_down, color: modeColor),
                    hint: Text(
                      'Select message type',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                    dropdownColor: Colors.grey[850],
                    menuMaxHeight: 150,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
