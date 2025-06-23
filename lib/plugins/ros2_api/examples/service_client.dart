// ignore_for_file: avoid_print

import 'package:ros2_api/ros2_api.dart';
import 'package:rosapi_msgs/srv.dart';

void main() async {
  // Initialize ROS2 client
  final ros2 = Ros2(url: 'ws://192.168.0.155:9090');
  ros2.connect();

  // Example 1: List all available services
  final servicesClient =
      ServiceClient<Services, ServicesRequest, ServicesResponse>(
    ros2: ros2,
    name: '/rosapi/services',
    type: Services().fullType,
    serviceType: Services(),
    timeout: 120,
  );

  try {
    print('Fetching available services...');
    final response = await servicesClient.call(ServicesRequest());
    print('Available services:');
    for (final service in response.services) {
      print('  - $service');
    }
  } catch (e) {
    print('Error calling service: $e');
  } finally {
    servicesClient.dispose();
  }

  // Example 2: Check if a specific service exists
  const serviceToCheck = '/example_service';
  final exists = await serviceExists(ros2, serviceToCheck);
  print('\nService check:');
  print('$serviceToCheck exists: $exists');

  // Clean up
  ros2.close();
}
