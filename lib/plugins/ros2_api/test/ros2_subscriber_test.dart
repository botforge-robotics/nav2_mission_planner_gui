import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:std_msgs/msg.dart';

final ros2 =
    Ros2(url: 'ws://localhost:9090'); // Update with your ROS bridge URL

void main() {
  group('Topic Subscriber Tests', () {
    setUp(() async {
      ros2.connect();
      await Future.delayed(const Duration(seconds: 2)); // Wait for connection
    });

    tearDown(() async {
      await ros2.close();
      await Future.delayed(const Duration(seconds: 1)); // Cleanup delay
    });

    test('Receives messages from /chatter topic', () async {
      // Arrange
      const expectedMessages = 5;
      var messagesReceived = 0;
      final receivedMessages = <String>[];
      final completer = Completer();

      // Setup subscriber
      final subscriber = Subscriber<StringMessage>(
        name: '/chatter',
        type: StringMessage().fullType,
        ros2: ros2,
        callback: (message) {
          messagesReceived++;
          receivedMessages.add(message.data);
          if (messagesReceived == expectedMessages) {
            completer.complete();
          }
        },
        prototype: StringMessage(),
      );

      // Act - Wait for messages with timeout
      await completer.future.timeout(const Duration(seconds: 10));

      // Assert
      expect(messagesReceived, greaterThan(0),
          reason: 'No messages received from /chatter topic');
      debugPrint('Received messages: $receivedMessages');

      // Cleanup
      await subscriber.shutdown();
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
