import 'dart:convert';
import 'package:std_msgs/msg.dart' as std_msgs;
import 'package:actionlib_msgs/msg.dart';

abstract class RosMessage<T> {
  String get fullType;
  String get messageDefinition;
  int getMessageSize();
  String toJsonString();
  Map<String, dynamic> toJson();
  T fromJson(Map<String, dynamic> jsonMap);
}

abstract class RosServiceMessage<C extends RosMessage<C>,
    R extends RosMessage<R>> {
  C get request;
  R get response;
  String get fullType;
  String get messageDefinition;
}

abstract class RosActionGoal<G extends RosMessage<G>,
    AG extends RosActionGoal<G, AG>> extends RosMessage<AG> {
  late std_msgs.Header header;
  late GoalID goal_id;
  late G goal;
}

abstract class RosActionFeedback<F extends RosMessage<F>,
    AF extends RosActionFeedback<F, AF>> extends RosMessage<AF> {
  late std_msgs.Header header;
  late GoalStatus status;
  late F feedback;
}

abstract class RosActionResult<R extends RosMessage<R>,
    AR extends RosActionResult<R, AR>> extends RosMessage<AR> {
  late std_msgs.Header header;
  late GoalStatus status;
  late R result;
}

abstract class RosActionMessage<
    G extends RosMessage<G>,
    AG extends RosActionGoal<G, AG>,
    F extends RosMessage<F>,
    AF extends RosActionFeedback<F, AF>,
    R extends RosMessage<R>,
    AR extends RosActionResult<R, AR>> {
  AG get actionGoal;
  AF get actionFeedback;
  AR get actionResult;
  G get goal;
  F get feedback;
  R get result;
  String get fullType;
  String get messageDefinition;
}

extension LenInBytes on String {
  int get lenInBytes => utf8.encode(this).length;
}
