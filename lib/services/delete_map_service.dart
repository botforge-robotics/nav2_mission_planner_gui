import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:nav2_mission_planner/providers/connection_provider.dart';
import 'package:nav2_mission_planner/providers/settings_provider.dart';
import 'package:nav2_mission_planner_interfaces/srv.dart';

class DeleteMapService {
  /// Calls the `/delete_map` ROS2 service; returns true on success.
  Future<bool> deleteMap(BuildContext context, String mapName) async {
    final connection = Provider.of<ConnectionProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);

    try {
      final client =
          ServiceClient<DeleteMap, DeleteMapRequest, DeleteMapResponse>(
        name: '/delete_map',
        ros2: connection.ros2Client!,
        type: DeleteMap().fullType,
        serviceType: DeleteMap(),
        timeout: settings.communicationTimeout.toDouble(),
      );

      final request = DeleteMapRequest(
        map_name: mapName,
        map_path: settings.mapsPath,
      );
      final response = await client.call(request);

      if (response.success) {
        return true;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete map: ${response.message}'),
            backgroundColor: Colors.red,
          ),
        );
        return false;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting map: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }
  }
}
