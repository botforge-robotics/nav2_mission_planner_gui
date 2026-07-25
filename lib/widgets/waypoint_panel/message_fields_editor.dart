import 'package:flutter/material.dart';
import '../../providers/ros2_data_provider.dart';
import '../../modals/mission.dart';
import 'form_generator.dart';
import '../../services/message_parser.dart';

class MessageFieldsEditor extends StatelessWidget {
  final MissionItem item;
  final Color modeColor;
  final ROS2DataProvider provider;
  final VoidCallback onChanged;

  const MessageFieldsEditor({
    super.key,
    required this.item,
    required this.modeColor,
    required this.provider,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (item.publishMsgType == null || item.publishMsgType!.isEmpty) {
      return _placeholder('Select a topic to load message structure');
    }

    final structure = provider.messageStructures[item.publishMsgType];

    if (structure == null) {
      return _error('Failed to load message structure');
    }

    // Ensure publishMessage initialized
    item.publishMessage ??=
        MessageParser.getDefaultValueForStructure(structure);

    return Container(
      padding: const EdgeInsets.all(5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: structure.entries.map((entry) {
          final fieldName = entry.key;
          final fieldDefinition = entry.value as Map<String, dynamic>;
          final currentValue = item.publishMessage![fieldName];

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(8),
            ),
            child: FormGenerator.generateFormField(
              fieldName,
              fieldDefinition,
              currentValue,
              (value) {
                item.publishMessage![fieldName] = value;
                onChanged();
              },
              modeColor,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _placeholder(String text) {
    return Center(
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
                style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                    fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  Widget _error(String text) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red[900]!.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[600]!, width: 1),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 32),
          const SizedBox(height: 12),
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
