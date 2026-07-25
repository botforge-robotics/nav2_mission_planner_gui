import 'package:flutter/material.dart';
import 'package:nav2_mission_planner/providers/connection_provider.dart';
import 'package:nav2_mission_planner_interfaces/srv.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:provider/provider.dart';
import 'package:nav2_mission_planner/providers/settings_provider.dart';

class MapListService {
  Future<List<String>> getMapList(BuildContext context) async {
    final connection = Provider.of<ConnectionProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);

    try {
      final serviceClient =
          ServiceClient<GetMapList, GetMapListRequest, GetMapListResponse>(
        name: '/get_map_list',
        ros2: connection.ros2Client,
        type: GetMapList().fullType,
        serviceType: GetMapList(),
        timeout: settings.communicationTimeout.toDouble(),
      );

      final request = GetMapListRequest(path: settings.mapsPath);
      final response = await serviceClient.call(request);

      if (response.success) {
        return response.maplist;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to get map list: ${response.message}'),
            backgroundColor: Colors.red.withOpacity(0.9),
          ),
        );
        return [];
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error fetching map list: ${e.toString()}'),
          backgroundColor: Colors.red.withOpacity(0.9),
        ),
      );
      return [];
    }
  }
}
