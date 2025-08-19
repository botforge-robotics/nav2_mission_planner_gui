import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:std_srvs/srv.dart'; // Import the service definitions for std_srvs

final ros2 =
    Ros2(url: 'ws://localhost:9090'); // Update with your ROS bridge URL

void main() {
  group('Service Server Tests', () {
    setUp(() async {
      ros2.connect();
      await Future.delayed(const Duration(seconds: 2)); // Wait for connection
    });

    tearDown(() async {
      await ros2.close();
      await Future.delayed(const Duration(seconds: 1)); // Cleanup delay
    });

    test('Handles SetBool service requests and waits for 3 calls', () async {
      // Arrange
      final serviceServer =
          ServiceServer<SetBool, SetBoolRequest, SetBoolResponse>(
        ros2: ros2,
        name: '/set_bool',
        type: SetBool().fullType,
        serviceType: SetBool(),
      );

      int requestCount = 0; // Counter for received requests

      // Act - Start the service server
      await serviceServer.serve((SetBoolRequest request) async {
        requestCount++;
        return SetBoolResponse()
          ..success = true
          ..message = 'Value set to ${request.data}';
      });

      // Wait for the service to be advertised
      await Future.delayed(const Duration(seconds: 2));

      // debugPrint a message indicating the service is ready
      debugPrint('Service /set_bool is ready to receive requests.');

      // Wait for up to 60 seconds for 3 service calls
      final completer = Completer<void>();
      Timer(const Duration(seconds: 60), () {
        if (!completer.isCompleted) {
          completer.completeError('Timeout waiting for service calls');
        }
      });

      // Wait for 3 requests
      while (requestCount < 3) {
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Complete the completer if we received 3 requests
      if (!completer.isCompleted) {
        completer.complete();
      }

      // Await the completer to ensure we don't exit early
      await completer.future;

      // Cleanup
      serviceServer.close(); // Stop the service server
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
