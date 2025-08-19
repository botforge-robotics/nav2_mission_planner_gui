import 'package:flutter/material.dart';
import '../../modals/mission.dart';
import '../../providers/ros2_data_provider.dart';
import 'section_card.dart';
import 'action_goal_editor.dart';

class ActionForm extends StatelessWidget {
  final MissionItem item;
  final ROS2DataProvider provider;
  final Color modeColor;
  final VoidCallback onChanged;

  const ActionForm({
    super.key,
    required this.item,
    required this.provider,
    required this.modeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionCard(
          title: 'Action Configuration',
          icon: Icons.play_arrow,
          color: modeColor,
          child: _buildActionDropdown(context),
        ),
        const SizedBox(height: 24),
        SectionCard(
          title: 'Result Options',
          icon: Icons.timer,
          color: modeColor,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Wait for Result',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500)),
              Switch(
                value: item.waitForActionResult ?? false,
                onChanged: (v) {
                  item.waitForActionResult = v;
                  onChanged();
                },
                activeColor: modeColor,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SectionCard(
          title: 'Goal Data',
          icon: Icons.flag,
          color: modeColor,
          child: ActionGoalEditor(
            item: item,
            modeColor: modeColor,
            provider: provider,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildActionDropdown(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Action Server Name',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            IconButton(
              icon: provider.isLoadingActions
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(modeColor)))
                  : Icon(Icons.refresh, color: modeColor),
              tooltip: 'Refresh Action Servers',
              onPressed: provider.isLoadingActions
                  ? null
                  : () async {
                      try {
                        await provider.fetchActionServers(forceRefresh: true);
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Failed to fetch action servers: $e'),
                            backgroundColor: Colors.red.withOpacity(0.9)));
                      }
                    },
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: provider.actionServers.contains(item.actionName)
              ? item.actionName
              : null,
          hint: Text(
              provider.actionServers.isEmpty
                  ? 'Click refresh to load action servers'
                  : 'Select an action server',
              style: const TextStyle(color: Colors.grey)),
          isExpanded: true,
          dropdownColor: Colors.grey[800],
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey[900],
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none),
          ),
          items: provider.actionServers
              .map((e) => DropdownMenuItem<String>(
                  value: e,
                  child: Text(e, style: const TextStyle(color: Colors.white))))
              .toList(),
          onChanged: (val) async {
            if (val == null) return;
            item.actionName = val;
            onChanged();
            final type = await provider.getActionType(val);
            item.actionType = type;
            final key = '${type}_goal';
            if (provider.messageStructures[key] == null) {
              await provider.getActionGoalStructure(val, type);
            }
            item.actionGoal = {};
            onChanged();
          },
        ),
      ],
    );
  }
}
