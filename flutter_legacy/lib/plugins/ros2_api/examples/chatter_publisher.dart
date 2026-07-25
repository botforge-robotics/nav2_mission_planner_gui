import 'package:flutter/foundation.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:std_msgs/msg.dart';

void main() async {
  final ros2 =
      Ros2(url: 'ws://192.168.0.155:9090'); // Replace with your ROS bridge URL
  ros2.connect();

  final publisher = Publisher<StringMessage>(
    name: '/chatter',
    type: StringMessage().fullType,
    ros2: ros2,
  );

  for (int i = 0; i < 20; i++) {
    await Future.delayed(const Duration(seconds: 1));
    publisher.publish(StringMessage(data: 'Hello ROS 2! Message number: $i'));
    debugPrint('Published: Hello ROS 2! Message number: $i');
  }

  await publisher.shutdown();
  ros2.close();
}
