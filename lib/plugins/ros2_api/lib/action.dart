import 'dart:async';
import 'ros2_websocket.dart';
import 'package:ros2_msg_utils/ros2_msg_utils.dart';

/// Action Client to send goals and monitor feedback/results
class ActionClient<
    T extends RosActionMessage<G, AG, F, AF, R, AR>,
    G extends RosMessage<G>,
    AG extends RosActionGoal<G, AG>,
    F extends RosMessage<F>,
    AF extends RosActionFeedback<F, AF>,
    R extends RosMessage<R>,
    AR extends RosActionResult<R, AR>> {
  ActionClient({
    required this.ros2,
    required this.actionName,
    required this.actionType,
    required this.actionMessage,
  });

  final Ros2 ros2;
  final String actionName;
  final String actionType;
  final T actionMessage;

  StreamSubscription? _feedbackSubscription;
  StreamSubscription? _resultSubscription;
  StreamController<F>? _feedbackController;
  Completer<R>? _resultCompleter;
  String? _goalId;
  bool _isCancelled = false;

  /// Send a goal to the action server
  Future<R> sendGoal(G goal, {void Function(F)? onFeedback}) async {
    _goalId = ros2.requestActionCaller(actionName);
    _isCancelled = false;

    // Setup feedback stream if callback provided
    if (onFeedback != null) {
      _feedbackController = StreamController<F>();
      _feedbackSubscription = ros2.stream
          .where((message) =>
              message['op'] == 'action_feedback' &&
              message['action'] == actionName &&
              message['id'] == _goalId)
          .listen((message) {
        final feedback = actionMessage.feedback
            .fromJson(message['values'] as Map<String, dynamic>);
        onFeedback(feedback);
      });
    }

    // Setup result handling
    _resultCompleter = Completer<R>();
    _resultSubscription = ros2.stream
        .where((message) =>
            message['op'] == 'action_result' &&
            message['action'] == actionName &&
            message['id'] == _goalId)
        .listen((message) {
      if (message['result'] != true) {
        _resultCompleter?.completeError(message['values'] ?? 'Action failed');
      } else {
        _resultCompleter?.complete(actionMessage.result
            .fromJson(message['values'] as Map<String, dynamic>));
      }
      // Only dispose if the goal was cancelled and we received status 5 (ABORTED)
      if (_isCancelled && message['status'] == 5) {
        dispose();
      }
    });

    // Send the goal
    ros2.send({
      'op': 'send_action_goal',
      'id': _goalId,
      'action': actionName,
      'feedback': onFeedback != null,
      'action_type': actionType,
      'args': goal.toJson(),
    });

    return _resultCompleter!.future;
  }

  /// Cancel the current goal
  void cancelGoal() {
    _isCancelled = true;
    ros2.send({
      'op': 'cancel_action_goal',
      'id': _goalId,
      'action': actionName,
    });
  }

  void dispose() {
    _feedbackSubscription?.cancel();
    _resultSubscription?.cancel();
    _feedbackController?.close();
    _feedbackSubscription = null;
    _resultSubscription = null;
    _feedbackController = null;
    _resultCompleter = null;
  }
}

/// Callback class for managing action state and feedback
class ActionCallback<R> {
  ActionCallback(this._goalId, this._actionServer);

  final String _goalId;
  final ActionServer _actionServer;
  bool _isPreemptRequested = false;
  bool get isPreemptRequested => _isPreemptRequested;

  void publishFeedback(dynamic feedback) {
    _actionServer.sendFeedback(_goalId, feedback);
  }

  void setPreempted({R? result, String errorMessage = ''}) {
    _isPreemptRequested = true;
    _actionServer.ros2.send({
      'op': 'action_result',
      'id': _goalId,
      'action': _actionServer.actionName,
      'values': {'error': errorMessage},
      'status': 6, // CANCELED status from action_msgs/msg/GoalStatus
      'result': false,
    });
  }

  void setSucceeded(R result) {
    _actionServer.ros2.send({
      'op': 'action_result',
      'id': _goalId,
      'action': _actionServer.actionName,
      'values': (result as dynamic).toJson(),
      'status': 4, // SUCCEEDED status from action_msgs/msg/GoalStatus
      'result': true,
    });
  }

  void setAborted(R result, {String errorMessage = ''}) {
    _actionServer.ros2.send({
      'op': 'action_result',
      'id': _goalId,
      'action': _actionServer.actionName,
      'values': {'error': errorMessage},
      'status': 5, // ABORTED status
      'result': false,
    });
  }
}

/// Action Server to handle goals and provide feedback/results
class ActionServer<
    T extends RosActionMessage<G, AG, F, AF, R, AR>,
    G extends RosMessage<G>,
    AG extends RosActionGoal<G, AG>,
    F extends RosMessage<F>,
    AF extends RosActionFeedback<F, AF>,
    R extends RosMessage<R>,
    AR extends RosActionResult<R, AR>> {
  ActionServer({
    required this.ros2,
    required this.actionName,
    required this.actionType,
    required this.actionMessage,
  });

  final Ros2 ros2;
  final String actionName;
  final String actionType;
  final T actionMessage;
  StreamSubscription? _subscription;
  final _activeGoals = <String, ActionCallback<R>>{};

  bool get isAdvertised => _subscription != null;

  /// Start the action server with goal handler
  Future<void> serve({
    required Future<void> Function(G, ActionCallback<R>) onGoal,
    required void Function(String) onCancel,
  }) async {
    if (isAdvertised) return;

    ros2.send({
      'op': 'advertise_action',
      'type': actionType,
      'action': actionName,
    });

    _subscription = ros2.stream.listen((message) async {
      switch (message['op']) {
        case 'send_action_goal':
          if (message['action'] == actionName) {
            final goalId = message['id'] as String;
            try {
              final goal = actionMessage.goal
                  .fromJson(message['args'] as Map<String, dynamic>);

              final callback = ActionCallback<R>(goalId, this);
              _activeGoals[goalId] = callback;

              await onGoal(goal, callback);

              _activeGoals.remove(goalId);
            } catch (e) {
              ros2.send({
                'op': 'action_result',
                'id': goalId,
                'action': actionName,
                'values': {'error': e.toString()},
                'status': 5, // ABORTED status
                'result': false,
              });
            }
          }
          break;
        case 'cancel_action_goal':
          if (message['action'] == actionName) {
            final goalId = message['id'] as String;
            final callback = _activeGoals[goalId];
            if (callback != null) {
              callback.setPreempted();
              onCancel(goalId);
              _activeGoals.remove(goalId);
            }
          }
          break;
      }
    });
  }

  /// Send feedback for a goal
  void sendFeedback(String goalId, F feedback) {
    ros2.send({
      'op': 'action_feedback',
      'id': goalId,
      'action': actionName,
      'values': feedback.toJson(),
    });
  }

  void close() {
    if (!isAdvertised) return;

    // Cancel all active goals
    for (final goalId in _activeGoals.keys) {
      _activeGoals[goalId]?.setPreempted();
    }
    _activeGoals.clear();

    ros2.send({
      'op': 'unadvertise_action',
      'action': actionName,
    });
    _subscription?.cancel();
    _subscription = null;
  }
}
