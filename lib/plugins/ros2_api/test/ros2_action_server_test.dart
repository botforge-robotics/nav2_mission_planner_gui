import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:action_tutorials_interfaces/action.dart'; // Import the action definitions

final ros2 =
    Ros2(url: 'ws://localhost:9090'); // Update with your ROS bridge URL

void main() {
  group('Action Server Tests', () {
    setUp(() async {
      ros2.connect();
      await Future.delayed(const Duration(seconds: 2)); // Wait for connection
    });

    tearDown(() async {
      await ros2.close();
      await Future.delayed(const Duration(seconds: 1)); // Cleanup delay
    });

    test('Handles Fibonacci action requests and supports preemption', () async {
      // Arrange
      final actionServer = ActionServer<
          Fibonacci,
          FibonacciGoal,
          FibonacciActionGoal,
          FibonacciFeedback,
          FibonacciActionFeedback,
          FibonacciResult,
          FibonacciActionResult>(
        ros2: ros2,
        actionName: '/fibonacci',
        actionType: Fibonacci().fullType,
        actionMessage: Fibonacci(),
      );

      // Act - Start the action server
      await actionServer.serve(
        onGoal: (FibonacciGoal goal,
            ActionCallback<FibonacciResult> callback) async {
          debugPrint('Goal received: ${goal.order}');

          int a = 0, b = 1;
          final feedback = FibonacciFeedback()..partial_sequence = [a];

          for (int i = 0; i < goal.order; i++) {
            if (callback.isPreemptRequested) {
              debugPrint('Goal preempted.');
              return;
            }

            int next = a + b;
            a = b;
            b = next;

            feedback.partial_sequence.add(a);
            callback.publishFeedback(feedback);
            await Future.delayed(const Duration(milliseconds: 500));
          }

          callback.setSucceeded(
            FibonacciResult()..sequence = feedback.partial_sequence,
          );
        },
        onCancel: (String goalId) {
          debugPrint('Goal $goalId canceled.');
        },
      );

      // Wait for the action server to be advertised
      debugPrint('Action server /fibonacci is ready to receive goals.');
      await Future.delayed(const Duration(seconds: 30));

      // Cleanup
      actionServer.close(); // Stop the action server
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
