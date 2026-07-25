import 'package:flutter/foundation.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:std_srvs/srv.dart';

/// Example demonstrating how to create a ROS2 service server using SetBool service
void main() async {
  // Initialize ROS2 with websocket connection
  final ros2 = Ros2(url: 'ws://192.168.0.155:9090');
  ros2.connect();

  // Wait for connection to be established
  await Future.delayed(const Duration(seconds: 1));

  try {
    // Set up the service server
    final serviceServer =
        ServiceServer<SetBool, SetBoolRequest, SetBoolResponse>(
      ros2: ros2,
      name: '/set_bool',
      type: SetBool().fullType,
      serviceType: SetBool(),
    );

    debugPrint('\nStarting SetBool service server at /set_bool');
    debugPrint('Server will run for 30 seconds...');

    // Start serving and handle requests
    await serviceServer.serve((SetBoolRequest request) async {
      debugPrint('\nReceived request: ${request.toJson()}');

      // Create and send response
      final response = SetBoolResponse(
        success: true,
        message: 'Value set to ${request.data}',
      );

      debugPrint('Sending response: ${response.toJson()}\n');
      return response;
    });

    // Keep the server running for 30 seconds
    await Future.delayed(const Duration(seconds: 30));
    debugPrint('Server shutting down...');

    // Cleanup
    serviceServer.close();
    await Future.delayed(const Duration(seconds: 1));
    await ros2.close();
  } catch (e) {
    debugPrint('Error occurred: $e');
    await ros2.close();
  }
}
