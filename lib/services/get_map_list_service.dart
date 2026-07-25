import 'package:flutter/material.dart';
import 'package:nav2_mission_planner/providers/connection_provider.dart';
import 'package:nav2_mission_planner_interfaces/srv.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:provider/provider.dart';
import 'package:nav2_mission_planner/providers/settings_provider.dart';
import 'package:nav2_mission_planner/constants/default_settings.dart';

class MapListService {
  Future<List<String>> getMapList(BuildContext context) async {
    final connection = Provider.of<ConnectionProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);

    if (!connection.isConnected) {
      return [];
    }

    // Always use NavProMini maps path (ignore stale prefs)
    final mapsPath = settings.mapsPath.trim().isEmpty
        ? DefaultSettings.defaultMapsFolder
        : settings.mapsPath;

    try {
      final serviceClient =
          ServiceClient<GetMapList, GetMapListRequest, GetMapListResponse>(
        name: '/get_map_list',
        ros2: connection.ros2Client,
        type: GetMapList().fullType,
        serviceType: GetMapList(),
        timeout: settings.communicationTimeout.toDouble(),
      );

      final request = GetMapListRequest(path: mapsPath);
      final response = await serviceClient.call(request);

      final maps = response.maplist
          .map((m) => m.replaceAll(RegExp(r'\.yaml$'), ''))
          .where((m) => m.isNotEmpty)
          .toList();

      if (maps.isEmpty && !response.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to get map list: ${response.message.isEmpty ? mapsPath : response.message}',
            ),
            backgroundColor: Colors.red.withOpacity(0.9),
          ),
        );
      }
      return maps;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error fetching map list: $e'),
          backgroundColor: Colors.red.withOpacity(0.9),
        ),
      );
      return [];
    }
  }
}
