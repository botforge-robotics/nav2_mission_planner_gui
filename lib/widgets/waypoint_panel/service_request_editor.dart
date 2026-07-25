import 'package:flutter/material.dart';
import '../../modals/mission.dart';
import '../../providers/ros2_data_provider.dart';
import 'form_generator.dart';
import '../../services/message_parser.dart';

class ServiceRequestEditor extends StatelessWidget {
  final MissionItem item;
  final Color modeColor;
  final ROS2DataProvider provider;
  final VoidCallback onChanged;

  const ServiceRequestEditor({
    super.key,
    required this.item,
    required this.modeColor,
    required this.provider,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (item.serviceType == null || item.serviceType!.isEmpty) {
      return _placeholder('Select a service to load request structure');
    }

    final key = '${item.serviceType}_request';
    final structure = provider.messageStructures[key];

    if (structure == null) {
      return provider.isLoadingMessageStructure
          ? _loading()
          : _placeholder('No request structure available');
    }

    // ensure request initialized
    item.serviceRequest ??=
        MessageParser.getDefaultValueForStructure(structure);

    if (structure.isEmpty) {
      return _placeholder("This service doesn't require any parameters");
    }

    return Container(
      padding: const EdgeInsets.all(5),
      child: Column(
        children: structure.entries.map((entry) {
          final fname = entry.key;
          final fdef = entry.value as Map<String, dynamic>;
          final current = item.serviceRequest![fname];
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
                item.serviceRequest![fname] = v;
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
