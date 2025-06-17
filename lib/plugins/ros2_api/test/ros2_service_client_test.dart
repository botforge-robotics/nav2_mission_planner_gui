import 'package:flutter_test/flutter_test.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:rosapi_msgs/srv.dart'; // Import the service definitions for rosapi

final ros2 =
    Ros2(url: 'ws://localhost:9090'); // Update with your ROS bridge URL

void main() {
  group('Service Client Tests', () {
    setUp(() async {
      ros2.connect();
      await Future.delayed(const Duration(seconds: 2)); // Wait for connection
    });

    tearDown(() async {
      await ros2.close();
      await Future.delayed(const Duration(seconds: 1)); // Cleanup delay
    });

    test('Calls /rosapi/services and prints result', () async {
      // Arrange
      final serviceClient =
          ServiceClient<Services, ServicesRequest, ServicesResponse>(
        ros2: ros2,
        name: '/rosapi/services',
        type: Services().fullType,
        serviceType: Services(),
      );

      final request =
          ServicesRequest(); // No parameters needed for this request

      // Act
      try {
        final response = await serviceClient.call(request);

        // Assert
        print('Available services: ${response.services}');
        expect(response.services, isNotEmpty, reason: 'No services available');
      } catch (e) {
        fail('Service call failed: $e');
      } finally {
        serviceClient.dispose(); // Cleanup
      }
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
