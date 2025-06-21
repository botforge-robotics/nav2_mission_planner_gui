import 'package:flutter/material.dart';
import '../../modals/mission.dart';
import '../../providers/ros2_data_provider.dart';
import 'section_card.dart';
import 'frequency_selector.dart';
import 'message_fields_editor.dart';
import '../../services/message_parser.dart';

class PublishForm extends StatelessWidget {
  final MissionItem item;
  final int index;
  final ROS2DataProvider provider;
  final Color modeColor;
  final VoidCallback onChanged;

  const PublishForm({
    super.key,
    required this.item,
    required this.index,
    required this.provider,
    required this.modeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Topic section
        SectionCard(
          title: 'Topic Configuration',
          icon: Icons.topic,
          color: modeColor,
          child: TopicSelector(
            item: item,
            modeColor: modeColor,
            provider: provider,
            onItemChanged: onChanged,
          ),
        ),
        const SizedBox(height: 24),
        // Frequency
        SectionCard(
          title: 'Publishing Frequency',
          icon: Icons.schedule,
          color: modeColor,
          child: FrequencySelector(
            item: item,
            modeColor: modeColor,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(height: 24),
        // Message data
        SectionCard(
          title: 'Message Data',
          icon: Icons.data_object,
          color: modeColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (item.publishMsgType != null) ...[
                Text(item.publishMsgType!,
                    style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                        fontStyle: FontStyle.italic)),
                const SizedBox(height: 16),
              ],
              MessageFieldsEditor(
                item: item,
                modeColor: modeColor,
                provider: provider,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Moved here from separate file to consolidate.
class TopicSelector extends StatelessWidget {
  final MissionItem item;
  final Color modeColor;
  final ROS2DataProvider provider;
  final VoidCallback onItemChanged;

  const TopicSelector({
    Key? key,
    required this.item,
    required this.modeColor,
    required this.provider,
    required this.onItemChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Select a topic',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            Container(
              decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(8)),
              child: IconButton(
                icon: provider.isLoadingTopics
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: modeColor, strokeWidth: 2))
                    : Icon(Icons.refresh, color: modeColor, size: 18),
                tooltip: 'Refresh Topics',
                onPressed: provider.isLoadingTopics
                    ? null
                    : () async {
                        try {
                          await provider.fetchTopics(forceRefresh: true);
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Failed to fetch topics: $e'),
                              backgroundColor: Colors.red));
                        }
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
              color: Colors.grey[850],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: item.publishTopic != null
                      ? modeColor.withOpacity(0.5)
                      : Colors.grey[600]!)),
          child: DropdownButtonFormField<String>(
            value: provider.topics.containsKey(item.publishTopic)
                ? item.publishTopic
                : null,
            hint: Row(children: const [
              Icon(Icons.topic, color: Colors.grey, size: 16),
              SizedBox(width: 8),
              Text('Select a topic', style: TextStyle(color: Colors.grey))
            ]),
            isExpanded: true,
            dropdownColor: Colors.grey[800],
            menuMaxHeight: 300,
            decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
            items: provider.topics.entries
                .map((e) => DropdownMenuItem<String>(
                    value: e.key,
                    child: Text(e.key,
                        style: const TextStyle(color: Colors.white))))
                .toList(),
            onChanged: (val) async {
              if (val == null) return;
              item.publishTopic = val;
              item.publishMessage = null;
              onItemChanged();

              try {
                final messageType = provider.topics[val] ?? '';
                final norm = MessageParser.normalizeMessageType(messageType);
                if (provider.messageStructures[norm] == null) {
                  await provider.getMessageStructure(val, messageType);
                }
                item.publishMsgType = norm;
                onItemChanged();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Failed to load message structure: $e'),
                    backgroundColor: Colors.red));
              }
            },
          ),
        ),
      ],
    );
  }
}
