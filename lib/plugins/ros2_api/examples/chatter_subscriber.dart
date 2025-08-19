import 'package:flutter/foundation.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:std_msgs/msg.dart';

void main() async {
  final ros2 =
      Ros2(url: 'ws://192.168.0.155:9090'); // Replace with your ROS bridge URL
  ros2.connect();

  final subscriber = Subscriber<StringMessage>(
    name: '/chatter',
    type: StringMessage().fullType,
    ros2: ros2,
    callback: (message) {
      debugPrint('Received message: ${message.data}');
    },
    prototype: StringMessage(),
  );

  // Keep the subscriber running for a while to receive messages
  await Future.delayed(const Duration(seconds: 20));

  await subscriber.shutdown();
  ros2.close();
}
