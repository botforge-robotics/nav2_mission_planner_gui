import 'package:flutter/material.dart';
import '../../modals/mission.dart';
import '../../providers/ros2_data_provider.dart';
import 'section_card.dart';
import 'service_request_editor.dart';

class ServiceForm extends StatelessWidget {
  final MissionItem item;
  final ROS2DataProvider provider;
  final Color modeColor;
  final VoidCallback onChanged;

  const ServiceForm({
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
        // Service configuration
        SectionCard(
          title: 'Service Configuration',
          icon: Icons.settings,
          color: modeColor,
          child: _buildServiceDropdown(context),
        ),
        const SizedBox(height: 24),
        // Wait toggle
        SectionCard(
          title: 'Response Options',
          icon: Icons.timer,
          color: modeColor,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Wait for Response',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500)),
              Switch(
                value: item.waitForServiceResponse ?? false,
                onChanged: (v) {
                  item.waitForServiceResponse = v;
                  onChanged();
                },
                activeColor: modeColor,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Request data
        SectionCard(
          title: 'Request Data',
          icon: Icons.send,
          color: modeColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (item.serviceType != null) ...[
                Text(item.serviceType!,
                    style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                        fontStyle: FontStyle.italic)),
                const SizedBox(height: 16),
              ],
              ServiceRequestEditor(
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

  Widget _buildServiceDropdown(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Select a service',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
              ),
              child: IconButton(
                icon: provider.isLoadingServices
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: modeColor, strokeWidth: 2),
                      )
                    : Icon(Icons.refresh, color: modeColor, size: 18),
                tooltip: 'Refresh Services',
                onPressed: provider.isLoadingServices
                    ? null
                    : () async {
                        try {
                          await provider.fetchServices(forceRefresh: true);
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Failed to fetch services: $e'),
                              backgroundColor: Colors.red.withOpacity(0.9)));
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
              color: item.serviceName != null
                  ? modeColor.withOpacity(0.5)
                  : Colors.grey[600]!,
            ),
          ),
          child: DropdownButtonFormField<String>(
            value: provider.services.containsKey(item.serviceName)
                ? item.serviceName
                : null,
            hint: Row(children: const [
              Icon(Icons.settings, color: Colors.grey, size: 16),
              SizedBox(width: 8),
              Text('Select a service', style: TextStyle(color: Colors.grey))
            ]),
            isExpanded: true,
            dropdownColor: Colors.grey[800],
            menuMaxHeight: 300,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            items: provider.services.entries
                .map((e) => DropdownMenuItem<String>(
                      value: e.key,
                      child: Text(e.key,
                          style: const TextStyle(color: Colors.white)),
                    ))
                .toList(),
            onChanged: (val) async {
              if (val == null) return;
              item.serviceName = val;
              onChanged();
              // get type and structure
              final type =
                  provider.services[val] ?? await provider.getServiceType(val);
              item.serviceType = type;
              final key = '${type}_request';
              if (provider.messageStructures[key] == null) {
                await provider.getServiceRequestStructure(val, type);
              }
              item.serviceRequest = {}; // reset
              onChanged();
            },
          ),
        ),
      ],
    );
  }
}
