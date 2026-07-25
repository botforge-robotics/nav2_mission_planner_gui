import 'dart:async';
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
    ros2.send({
      'op': 'advertise',
      'topic': name,
      'type': type,
    });
  }

  void publish(T message) {
    String serializedMessage = message.toJsonString();
    ros2.send('{"op": "publish", "topic": "$name", "msg": $serializedMessage}');
  }

  Future<void> shutdown() async {
    unadvertise();
  }

  void unadvertise() {
    ros2.send({
      'op': 'unadvertise',
      'topic': name,
    });
  }
}

class Subscriber<T extends RosMessage<T>> {
  final String name;
  final String type;
  final Ros2 ros2;
  final Function(T) callback;
  final T _prototype;
  final Map<String, dynamic>? qos;
  StreamSubscription? _subscription;

  Subscriber({
    required this.name,
    required this.type,
    required this.ros2,
    required this.callback,
    required T prototype,
    this.qos,
  }) : _prototype = prototype {
    subscribe();
  }

  void subscribe() {
    final msg = <String, dynamic>{
      'op': 'subscribe',
      'topic': name,
      'type': type,
    };
    // Needed for /map (map_server / slam use TRANSIENT_LOCAL)
    if (qos != null) {
      msg['qos'] = qos;
    }
    ros2.send(msg);

    _subscription = ros2.stream.listen((data) {
      if (data['op'] == 'publish' && data['topic'] == name) {
        try {
          final messageData = data['msg'] as Map<String, dynamic>;
          callback(_prototype.fromJson(messageData));
        } catch (e) {
          debugPrint('Error parsing $name: $e');
        }
      }
    }, onError: (error) {
      debugPrint('Error receiving message: $error');
    });
  }

  Future<void> shutdown() async {
    unsubscribe();
  }

  void unsubscribe() {
    _subscription?.cancel();
    _subscription = null;
    ros2.send({
      'op': 'unsubscribe',
      'topic': name,
      'type': type,
    });
  }
}

/// Dynamic Publisher for publishing to any topic without predefined message types
class DynamicPublisher {
  DynamicPublisher({
    required this.ros2,
    required this.topicName,
    required this.topicType,
  });

  final Ros2 ros2;
  final String topicName;
  final String topicType;
  bool _isAdvertised = false;

  bool get isAdvertised => _isAdvertised;

  /// Advertise the topic
  void advertise() {
    if (_isAdvertised) return;

    ros2.send({
      'op': 'advertise',
      'topic': topicName,
      'type': topicType,
    });
    _isAdvertised = true;
  }

  /// Publish a message to the topic
  void publish(Map<String, dynamic> message) {
    if (!_isAdvertised) advertise();

    ros2.send({
      'op': 'publish',
      'topic': topicName,
      'msg': message,
    });
  }

  /// Publish a message with custom serialization
  void publishRaw(String serializedMessage) {
    if (!_isAdvertised) advertise();

    ros2.send(
        '{"op": "publish", "topic": "$topicName", "msg": $serializedMessage}');
  }

  /// Unadvertise the topic
  void unadvertise() {
    if (!_isAdvertised) return;

    ros2.send({
      'op': 'unadvertise',
      'topic': topicName,
    });
    _isAdvertised = false;
  }

  /// Shutdown the publisher
  Future<void> shutdown() async {
    unadvertise();
  }
}

/// Dynamic Subscriber for subscribing to any topic without predefined message types
class DynamicSubscriber {
  DynamicSubscriber({
    required this.ros2,
    required this.topicName,
    required this.topicType,
    required this.onMessage,
  });

  final Ros2 ros2;
  final String topicName;
  final String topicType;
  final Function(Map<String, dynamic>) onMessage;
  StreamSubscription? _subscription;
  bool _isSubscribed = false;

  bool get isSubscribed => _isSubscribed;

  /// Subscribe to the topic
  void subscribe() {
    if (_isSubscribed) return;

    ros2.send({
      'op': 'subscribe',
      'topic': topicName,
      'type': topicType,
    });

    _subscription = ros2.stream.listen((data) {
      if (data['op'] == 'publish' && data['topic'] == topicName) {
        final messageData = data['msg'] as Map<String, dynamic>;
        onMessage(messageData);
      }
    }, onError: (error) {
      debugPrint('Error receiving message on $topicName: $error');
    });

    _isSubscribed = true;
  }

  /// Unsubscribe from the topic
  void unsubscribe() {
    if (!_isSubscribed) return;

    ros2.send({
      'op': 'unsubscribe',
      'topic': topicName,
      'type': topicType,
    });

    _subscription?.cancel();
    _subscription = null;
    _isSubscribed = false;
  }

  /// Shutdown the subscriber
  Future<void> shutdown() async {
    unsubscribe();
  }
}
