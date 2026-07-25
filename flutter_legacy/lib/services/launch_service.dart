import 'package:flutter/material.dart';
import 'package:nav2_mission_planner/providers/settings_provider.dart';
import 'package:nav2_mission_planner/providers/connection_provider.dart';
import 'package:nav2_mission_planner_interfaces/srv.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:provider/provider.dart';

class LaunchManager extends ChangeNotifier {
  final Map<String, String> _activeLaunches = {}; // unique_id -> description
  SessionType _activeSession = SessionType.none;
  SessionType get activeSession => _activeSession;

  Map<String, String> get activeLaunches => Map.unmodifiable(_activeLaunches);

  Future<bool> startMapping(BuildContext context) async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final connection = Provider.of<ConnectionProvider>(context, listen: false);

    final parts = settings.mappingLaunchFile.split('/');
    if (parts.length != 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid launch file format'),
          backgroundColor: Colors.red.withOpacity(0.9),
        ),
      );
      return false;
    }

    // Ensure the launch file ends with ".launch.py"
    String launchFile = parts[1];
    if (!launchFile.endsWith('.launch.py')) {
      launchFile = '$launchFile.launch.py';
    }

    try {
      final serviceClient = ServiceClient<LaunchWithArgs, LaunchWithArgsRequest,
          LaunchWithArgsResponse>(
        name: '/launch_with_args',
        ros2: connection.ros2Client,
        type: LaunchWithArgs().fullType,
        serviceType: LaunchWithArgs(),
        timeout: settings.communicationTimeout.toDouble(),
      );

      final request = LaunchWithArgsRequest(
        package: parts[0],
        launch_file: launchFile,
        arguments: settings.mappingArgs
            .map((arg) => '${arg['name']}:=${arg['value']}')
            .join(' '),
      );
      // Launch request
      final response = await serviceClient.call(request);
      if (response.success) {
        // Track the unique_id and description
        _activeLaunches[response.unique_id] =
            '${parts[0]}/${parts[1]} ${settings.mappingArgs.map((arg) => '${arg['name']}:=${arg['value']}').join(' ')}';
        notifyListeners();
        _activeSession = SessionType.mapping;
        return true;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start mapping: ${response.message}'),
            backgroundColor: Colors.red.withOpacity(0.9),
          ),
        );
        _activeSession = SessionType.none;
        return false;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error calling launch service: $e'),
          backgroundColor: Colors.red.withOpacity(0.9),
        ),
      );
      _activeSession = SessionType.none;
      return false;
    }
  }

  Future<void> stopLaunch(BuildContext context, String uniqueId) async {
    final connection = Provider.of<ConnectionProvider>(context, listen: false);
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    try {
      final serviceClient =
          ServiceClient<StopLaunch, StopLaunchRequest, StopLaunchResponse>(
        name: '/stop_launch',
        ros2: connection.ros2Client,
        type: StopLaunch().fullType,
        serviceType: StopLaunch(),
        timeout: settings.communicationTimeout.toDouble(),
      );

      final request = StopLaunchRequest(unique_id: uniqueId);
      await serviceClient.call(request);
      _activeLaunches.remove(uniqueId);
      notifyListeners();
      _activeSession = SessionType.none;
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> saveMap(BuildContext context, String mapName) async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final connection = Provider.of<ConnectionProvider>(context, listen: false);

    // Hardcode the launch file components
    final package = 'nav2_mission_planner';
    final launchFile = 'save_map.launch.py';

    // Prepare arguments with map_name and map_path
    final args = [
      ...settings.saveMapArgs,
      {'name': 'map_name', 'value': mapName},
      {'name': 'map_path', 'value': settings.mapsPath}, // Add map_path argument
    ];

    try {
      final serviceClient = ServiceClient<LaunchWithArgs, LaunchWithArgsRequest,
          LaunchWithArgsResponse>(
        name: '/launch_with_args',
        ros2: connection.ros2Client,
        type: LaunchWithArgs().fullType,
        serviceType: LaunchWithArgs(),
        timeout: settings.communicationTimeout.toDouble(),
      );

      final request = LaunchWithArgsRequest(
        package: package,
        launch_file: launchFile,
        arguments:
            args.map((arg) => '${arg['name']}:=${arg['value']}').join(' '),
      );

      final response = await serviceClient.call(request);
      return response.success;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving map: ${e.toString()}'),
          backgroundColor: Colors.red.withOpacity(0.9),
        ),
      );
      return false;
    }
  }

  Future<bool> startNavigation(BuildContext context, String mapName) async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final connection = Provider.of<ConnectionProvider>(context, listen: false);

    final parts = settings.navigationLaunchFile.split('/');
    if (parts.length != 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid navigation launch file format'),
          backgroundColor: Colors.red.withOpacity(0.9),
        ),
      );
      return false;
    }

    try {
      final serviceClient = ServiceClient<LaunchWithArgs, LaunchWithArgsRequest,
          LaunchWithArgsResponse>(
        name: '/launch_with_args',
        ros2: connection.ros2Client,
        type: LaunchWithArgs().fullType,
        serviceType: LaunchWithArgs(),
        timeout: settings.communicationTimeout.toDouble(),
      );

      // Get arguments directly from settings
      final args = [
        ...settings.navigationArgs,
        {'name': 'map', 'value': '$mapName.yaml'},
      ];

      final request = LaunchWithArgsRequest(
        package: parts[0],
        launch_file: parts[1].endsWith('.launch.py')
            ? parts[1]
            : '${parts[1]}.launch.py',
        arguments:
            args.map((arg) => '${arg['name']}:=${arg['value']}').join(' '),
      );

      final response = await serviceClient.call(request);
      if (response.success) {
        _activeLaunches[response.unique_id] =
            '${parts[0]}/${parts[1]} ${args.map((a) => '${a['name']}:=${a['value']}').join(' ')}';
        notifyListeners();
        _activeSession = SessionType.navigation;
        return true;
      }
      return false;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Navigation error: ${e.toString()}'),
          backgroundColor: Colors.red.withOpacity(0.9),
        ),
      );
      return false;
    }
  }
}

enum SessionType { none, mapping, navigation }
