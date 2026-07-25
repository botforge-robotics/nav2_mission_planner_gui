import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:action_tutorials_interfaces/action.dart'; // Import the action definitions

void main() async {
  final ros2 =
      Ros2(url: 'ws://192.168.0.155:9090'); // Update with your ROS bridge URL
  ros2.connect();
  await Future.delayed(const Duration(seconds: 2)); // Wait for connection

  // Create the action client
  final actionClient = ActionClient<
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

  final goal = FibonacciGoal(order: 5); // Example goal

  // Send the goal and handle feedback
  try {
    final result = await actionClient.sendGoal(goal,
        onFeedback: (FibonacciFeedback feedback) {
      debugPrint('Received feedback: ${feedback.partial_sequence}');
    });

    // debugPrint the result
    debugPrint('Received result: ${result.sequence}');
  } catch (e) {
    debugPrint('Action call failed: $e');
  } finally {
    actionClient.dispose(); // Cleanup
    await ros2.close(); // Close the ROS2 connection
  }
}
