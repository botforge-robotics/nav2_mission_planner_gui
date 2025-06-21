import 'package:flutter/material.dart';
import '../../modals/mission.dart';
import '../../providers/ros2_data_provider.dart';
import 'form_generator.dart';
import '../../services/message_parser.dart';

class ActionGoalEditor extends StatelessWidget {
  final MissionItem item;
  final Color modeColor;
  final ROS2DataProvider provider;
  final VoidCallback onChanged;

  const ActionGoalEditor({
    Key? key,
    required this.item,
    required this.modeColor,
    required this.provider,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (item.actionType == null || item.actionType!.isEmpty) {
      return _placeholder('Select an action to load goal structure');
    }

    final key = '${item.actionType}_goal';
    final structure = provider.messageStructures[key];

    if (structure == null) {
      return provider.isLoadingMessageStructure
          ? _loading()
          : _placeholder('No goal structure available');
    }

    item.actionGoal ??= MessageParser.getDefaultValueForStructure(structure);

    if (structure.isEmpty) {
      return _placeholder("This action doesn't require any goal parameters");
    }

    return Container(
      padding: const EdgeInsets.all(5),
      child: Column(
        children: structure.entries.map((entry) {
          final fname = entry.key;
          final fdef = entry.value as Map<String, dynamic>;
          final current = item.actionGoal![fname];
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8)),
            child: FormGenerator.generateFormField(
              fname,
              fdef,
              current,
              (v) {
                item.actionGoal![fname] = v;
                onChanged();
              },
              modeColor,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _placeholder(String text) => Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey[850],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[600]!),
          ),
          child: Column(
            children: [
              const Icon(Icons.info_outline, color: Colors.grey, size: 32),
              const SizedBox(height: 12),
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 14)),
            ],
          ),
        ),
      );

  Widget _loading() => Center(
        child: Column(
          children: const [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
}
