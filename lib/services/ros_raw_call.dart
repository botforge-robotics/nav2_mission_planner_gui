import 'dart:async';

import 'package:ros2_api/ros2_api.dart';

/// Generic, untyped ROS service/action calls — the counterpart to
/// [ServiceClient]/[ActionClient]'s own typed calls, for the Developer
/// Tools screen's Services/Actions tabs where the type is only known as a
/// string picked at runtime (rosapi's own `/rosapi/service_type` and
/// `/rosapi/action_type`), not a generated Dart class. Talks the exact same
/// rosbridge wire protocol those typed clients use underneath
/// (`call_service`/`service_response`, `send_action_goal`/`action_result`)
/// — see ros2_api's own service.dart/action.dart — just with a raw JSON
/// map instead of a `RosMessage` subclass on both ends.

/// Calls any ROS service by name+type with a raw JSON request, returning
/// the raw JSON response.
Future<Map<String, dynamic>> callServiceRaw(
  Ros2 ros2, {
  required String service,
  required String type,
  required Map<String, dynamic> args,
  Duration timeout = const Duration(seconds: 10),
}) {
  final id = ros2.requestServiceCaller(service);
  final completer = Completer<Map<String, dynamic>>();
  late final StreamSubscription sub;
  sub = ros2.stream
      .where((m) =>
          m['op'] == 'service_response' &&
          m['service'] == service &&
          m['id'] == id)
      .listen((m) {
    sub.cancel();
    if (completer.isCompleted) return;
    if (m['result'] != true) {
      completer.completeError(
          Exception((m['values'] ?? 'Service call failed').toString()));
    } else {
      completer.complete((m['values'] as Map?)?.cast<String, dynamic>() ?? {});
    }
  });
  ros2.send({
    'op': 'call_service',
    'id': id,
    'service': service,
    'type': type,
    'args': args,
    'timeout': timeout.inSeconds.toDouble(),
  });
  return completer.future.timeout(timeout, onTimeout: () {
    sub.cancel();
    throw TimeoutException(
        'No response from $service within ${timeout.inSeconds}s');
  });
}

/// Sends any ROS action goal by name+type with a raw JSON goal, returning
/// the raw JSON result once the action reaches a terminal state
/// (SUCCEEDED — anything else completes as an error, same convention
/// [ActionClient.sendGoal] uses).
Future<Map<String, dynamic>> sendActionGoalRaw(
  Ros2 ros2, {
  required String action,
  required String actionType,
  required Map<String, dynamic> goal,
  Duration timeout = const Duration(minutes: 2),
}) {
  final id = ros2.requestActionCaller(action);
  final completer = Completer<Map<String, dynamic>>();
  late final StreamSubscription sub;
  sub = ros2.stream
      .where((m) =>
          m['op'] == 'action_result' && m['action'] == action && m['id'] == id)
      .listen((m) {
    sub.cancel();
    if (completer.isCompleted) return;
    final status = m['status'];
    if (status == 4) {
      completer.complete((m['values'] as Map?)?.cast<String, dynamic>() ?? {});
    } else {
      completer.completeError(
          Exception('Goal ended with status $status: ${m['values']}'));
    }
  });
  ros2.send({
    'op': 'send_action_goal',
    'id': id,
    'action': action,
    'action_type': actionType,
    'feedback': false,
    'args': goal,
  });
  return completer.future.timeout(timeout, onTimeout: () {
    sub.cancel();
    throw TimeoutException(
        'No result from $action within ${timeout.inMinutes}m');
  });
}

/// Subscribes to any topic by name+type, delivering raw decoded messages
/// until [cancel] is called on the returned handle — for the Developer
/// Tools screen's live "peek at a topic" viewer.
class RawTopicSubscription {
  RawTopicSubscription._(this._ros2, this._topic, this._sub);

  final Ros2 _ros2;
  final String _topic;
  final StreamSubscription<Map<String, dynamic>> _sub;

  static RawTopicSubscription start(
    Ros2 ros2, {
    required String topic,
    required String type,
    required void Function(Map<String, dynamic>) onMessage,
  }) {
    final sub = ros2.stream
        .where((m) => m['op'] == 'publish' && m['topic'] == topic)
        .listen((m) =>
            onMessage((m['msg'] as Map?)?.cast<String, dynamic>() ?? {}));
    ros2.send({'op': 'subscribe', 'topic': topic, 'type': type});
    return RawTopicSubscription._(ros2, topic, sub);
  }

  void cancel() {
    _sub.cancel();
    _ros2.send({'op': 'unsubscribe', 'topic': _topic});
  }
}
