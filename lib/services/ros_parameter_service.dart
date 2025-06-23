import 'package:flutter/foundation.dart';
import 'package:ros2_api/ros2_api.dart';
import 'dart:convert';
import '../providers/connection_provider.dart';
import 'package:rosapi_msgs/srv.dart';
import '../constants/default_settings.dart';
import '../providers/settings_provider.dart';

class RosParameterService {
  static Future<bool> setParameter(ConnectionProvider connectionProvider,
      SettingsProvider settingsProvider, String name, dynamic value) async {
    if (!connectionProvider.isConnected ||
        connectionProvider.ros2Client == null) {
      throw Exception('Not connected to ROS2');
    }

    try {
      final serviceClient =
          ServiceClient<SetParam, SetParamRequest, SetParamResponse>(
        name: '/rosapi/set_param',
        ros2: connectionProvider.ros2Client!,
        type: SetParam().fullType,
        serviceType: SetParam(),
        timeout: settingsProvider.communicationTimeout.toDouble(),
      );

      final response = await serviceClient.call(SetParamRequest(
        name: name,
        value: json.encode(value),
      ));

      debugPrint(
          'Parameter $name set to $value success: ${response.successful}');
      return response.successful;
    } catch (e) {
      debugPrint('Error setting parameter $name: $e');
      rethrow;
    }
  }

  static Future<dynamic> getParameter(ConnectionProvider connectionProvider,
      SettingsProvider settingsProvider, String name) async {
    if (!connectionProvider.isConnected ||
        connectionProvider.ros2Client == null) {
      throw Exception('Not connected to ROS2');
    }

    try {
      final serviceClient =
          ServiceClient<GetParam, GetParamRequest, GetParamResponse>(
        name: '/rosapi/get_param',
        ros2: connectionProvider.ros2Client!,
        type: GetParam().fullType,
        serviceType: GetParam(),
        timeout: settingsProvider.communicationTimeout.toDouble(),
      );

      final response = await serviceClient.call(GetParamRequest(
        name: name,
        default_value: '',
      ));

      return json.decode(response.value);
    } catch (e) {
      debugPrint('Error getting parameter $name: $e');
      rethrow;
    }
  }
}
