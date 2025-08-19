import 'package:flutter/foundation.dart';

import 'ros2_websocket.dart';
import 'package:ros2_msg_utils/ros2_msg_utils.dart';

class Publisher<T extends RosMessage<T>> {
  final String name;
  final String type;
  final Ros2 ros2;

  Publisher({required this.name, required this.type, required this.ros2}) {
    advertise();
  }

  void advertise() {
    ros2.send('{"op": "advertise", "topic": "$name", "type": "$type"}');
  }

  void publish(T message) {
    String serializedMessage = message.toJsonString();
    ros2.send('{"op": "publish", "topic": "$name", "msg": $serializedMessage}');
  }

  Future<void> shutdown() async {
    unadvertise();
  }

  void unadvertise() {
    ros2.send('{"op": "unadvertise", "topic": "$name"}');
  }
}

class Subscriber<T extends RosMessage<T>> {
  final String name;
  final String type;
  final Ros2 ros2;
  final Function(T) callback;
  final T _prototype;

  Subscriber({
    required this.name,
    required this.type,
    required this.ros2,
    required this.callback,
    required T prototype,
  }) : _prototype = prototype {
    subscribe();
  }

  void subscribe() {
    ros2.send('{"op": "subscribe", "topic": "$name", "type": "$type"}');

    ros2.stream.listen((data) {
      if (data['op'] == 'publish' && data['topic'] == name) {
        final messageData = data['msg'] as Map<String, dynamic>;
        callback(_prototype.fromJson(messageData));
      }
    }, onError: (error) {
      debugPrint('Error receiving message: $error');
    });
  }

  Future<void> shutdown() async {
    unsubscribe();
  }

  void unsubscribe() {
    ros2.send('{"op": "unsubscribe", "topic": "$name"}');
  }
}
