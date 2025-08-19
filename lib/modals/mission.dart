import 'package:flutter/material.dart';
import 'dart:convert';

class Mission {
  final String missionName;
  final String missionDescription;
  final String mapName;
  final List<MissionItem> items;

  Mission({
    required this.missionName,
    required this.missionDescription,
    required this.mapName,
    required this.items,
  });

  factory Mission.fromJson(Map<String, dynamic> json) {
    return Mission(
      missionName: json['mission_name'] as String,
      missionDescription: json['mission_description'] as String,
      mapName: json['map_name'] as String,
      items: (json['items'] as List)
          .map((item) => MissionItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mission_name': missionName,
      'mission_description': missionDescription,
      'map_name': mapName,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }

  String toJsonString() {
    return jsonEncode(toJson());
  }

  factory Mission.fromJsonString(String jsonString) {
    return Mission.fromJson(jsonDecode(jsonString));
  }

  // Add this helper method
  static List<Mission> filterByMap(
      Map<String, Mission> missions, String mapName) {
    return missions.values
        .where((mission) => mission.mapName == mapName)
        .toList();
  }

  // Legacy support - convert waypoints to items
  List<Waypoint> get waypoints => items
      .where((item) => item.type == MissionItemType.goto)
      .map((item) => Waypoint(
            id: item.id ?? '',
            position: item.position ?? Position(x: 0, y: 0, theta: 0),
            events: [],
            name: item.name,
          ))
      .toList();
}

enum MissionItemType {
  goto(
    displayName: 'GOTO Position',
    icon: Icons.navigation,
    color: Colors.blue,
  ),
  wait(
    displayName: 'Wait',
    icon: Icons.timer,
    color: Colors.amber,
  ),
  publish(
    displayName: 'Publish',
    icon: Icons.publish,
    color: Colors.red,
  ),
  callService(
    displayName: 'Service',
    icon: Icons.settings,
    color: Colors.teal,
  ),
  callAction(
    displayName: 'Action',
    icon: Icons.play_arrow,
    color: Colors.green,
  ),
  captureImage(
    displayName: 'Capture Image',
    icon: Icons.camera_alt,
    color: Colors.orange,
  );

  final String displayName;
  final IconData icon;
  final Color color;

  const MissionItemType({
    required this.displayName,
    required this.icon,
    required this.color,
  });

  String get name => toString().split('.').last;
}

extension MissionItemTypeExtension on MissionItemType {
  String get displayName {
    return this.displayName;
  }

  Color get color {
    return this.color;
  }

  IconData get icon {
    return this.icon;
  }
}

class MissionItem {
  String? id;
  MissionItemType type;
  String? name;
  Position? position;

  // WAIT parameters
  double? waitDuration;

  // PUBLISH parameters
  String? publishTopic;
  String? publishMsgType;
  Map<String, dynamic>? publishMessage;
  String? publishFrequencyType; // 'once', 'until_next_goal', 'duration', 'hz'
  double? publishDuration;
  double? publishFrequency;

  // SERVICE parameters
  String? serviceName;
  String? serviceType;
  Map<String, dynamic>? serviceRequest;
  bool? waitForServiceResponse;

  // ACTION parameters
  String? actionName;
  String? actionType;
  Map<String, dynamic>? actionGoal;
  bool? waitForActionResult;

  // Warning flag for structure changes
  bool hasStructureWarning = false;

  MissionItem({
    this.id,
    required this.type,
    this.name,
    this.position,
    this.waitDuration,
    this.publishTopic,
    this.publishMsgType,
    this.publishMessage,
    this.publishFrequencyType,
    this.publishDuration,
    this.publishFrequency,
    this.serviceName,
    this.serviceType,
    this.serviceRequest,
    this.waitForServiceResponse,
    this.actionName,
    this.actionType,
    this.actionGoal,
    this.waitForActionResult,
    this.hasStructureWarning = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'name': name,
      'position': position?.toJson(),
      'waitDuration': waitDuration,
      'publishTopic': publishTopic,
      'publishMsgType': publishMsgType,
      'publishMessage': publishMessage,
      'publishFrequencyType': publishFrequencyType,
      'publishDuration': publishDuration,
      'publishFrequency': publishFrequency,
      'serviceName': serviceName,
      'serviceType': serviceType,
      'serviceRequest': serviceRequest,
      'waitForServiceResponse': waitForServiceResponse,
      'actionName': actionName,
      'actionType': actionType,
      'actionGoal': actionGoal,
      'waitForActionResult': waitForActionResult,
      'hasStructureWarning': hasStructureWarning,
    };
  }

  factory MissionItem.fromJson(Map<String, dynamic> json) {
    return MissionItem(
      id: json['id'],
      type: MissionItemType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => MissionItemType.goto,
      ),
      name: json['name'],
      position:
          json['position'] != null ? Position.fromJson(json['position']) : null,
      waitDuration: json['waitDuration']?.toDouble(),
      publishTopic: json['publishTopic'],
      publishMsgType: json['publishMsgType'],
      publishMessage: json['publishMessage'],
      publishFrequencyType: json['publishFrequencyType'],
      publishDuration: json['publishDuration']?.toDouble(),
      publishFrequency: json['publishFrequency']?.toDouble(),
      serviceName: json['serviceName'],
      serviceType: json['serviceType'],
      serviceRequest: json['serviceRequest'],
      waitForServiceResponse: json['waitForServiceResponse'],
      actionName: json['actionName'],
      actionType: json['actionType'],
      actionGoal: json['actionGoal'],
      waitForActionResult: json['waitForActionResult'],
      hasStructureWarning: json['hasStructureWarning'] ?? false,
    );
  }

  /// Returns a descriptive subtitle for this item
  String get subtitle {
    switch (type) {
      case MissionItemType.goto:
        if (name != null) {
          return 'Go to $name';
        } else if (position != null) {
          return 'Position (${position!.x.toStringAsFixed(2)}, ${position!.y.toStringAsFixed(2)})';
        }
        return 'No position set';

      case MissionItemType.wait:
        return 'Wait for ${waitDuration?.toStringAsFixed(1) ?? '0'} seconds';

      case MissionItemType.publish:
        String details = publishTopic ?? 'No topic set';

        // Add frequency information if available
        if (publishFrequencyType == 'hz' && publishFrequency != null) {
          details += ' • $publishFrequency Hz';
        } else if (publishFrequencyType == 'duration' &&
            publishDuration != null) {
          details += ' • ${publishDuration}s';
        } else if (publishFrequencyType == 'once') {
          details += ' • Once';
        }

        return details;

      case MissionItemType.callService:
        String details = serviceName ?? 'No service set';

        // Add waiting information
        if (waitForServiceResponse == true) {
          details += ' • Wait for response';
        }

        return details;

      case MissionItemType.callAction:
        String details = actionName ?? 'No action set';

        // Add waiting information
        if (waitForActionResult == true) {
          details += ' • Wait for result';
        }

        return details;

      case MissionItemType.captureImage:
        return 'Capture and save camera image';
    }
  }

  String get displayTitle {
    return name ?? '${type.displayName} ${(id?.substring(0, 8)) ?? ''}';
  }
}

// Legacy Waypoint class for backward compatibility
class Waypoint {
  final String id;
  final String? bookmarkId;
  final String? name;
  final Position position;
  final List<Event> events;

  Waypoint({
    required this.id,
    this.bookmarkId,
    this.name,
    required this.position,
    required this.events,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'position': position.toJson(),
      'events': events.map((e) => e.toJson()).toList(),
      'name': name,
    };
  }

  factory Waypoint.fromJson(Map<String, dynamic> json) {
    return Waypoint(
      id: json['id'] as String,
      bookmarkId: json['bookmarkId'] as String?,
      name: json['name'] as String?,
      position: Position.fromJson(json['position'] as Map<String, dynamic>),
      events: (json['events'] as List<dynamic>?)
              ?.map((e) => Event.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class Position {
  final double x;
  final double y;
  final double theta;

  Position({
    required this.x,
    required this.y,
    required this.theta,
  });

  factory Position.fromJson(Map<String, dynamic> json) {
    return Position(
      x: json['x'] as double,
      y: json['y'] as double,
      theta: json['theta'] as double,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'x': x,
      'y': y,
      'theta': theta,
    };
  }
}

class Event {
  final String type;
  final Map<String, dynamic> parameters;

  Event({
    required this.type,
    required this.parameters,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    final parameters = Map<String, dynamic>.from(json);
    parameters.remove('type');
    return Event(type: type, parameters: parameters);
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      ...parameters,
    };
  }

  // Helper methods for specific event types
  bool get isWait => type == 'wait';
  bool get isTopicPub => type == 'topic_pub';
  bool get isTopicSub => type == 'topic_sub';
  bool get isCaptureImage => type == 'capture_image';
  bool get isServiceCall => type == 'service_call';
  bool get isActionGoal => type == 'action_goal';

  // Getters for common parameters
  double? get waitDuration =>
      isWait ? parameters['duration_sec'] as double? : null;
  String? get topic => isTopicPub ? parameters['topic'] as String? : null;
  String? get msgType => isTopicPub ? parameters['msg_type'] as String? : null;
  Map<String, dynamic>? get message =>
      isTopicPub ? parameters['message'] as Map<String, dynamic>? : null;
  String? get service =>
      isServiceCall ? parameters['service'] as String? : null;
  String? get serviceType =>
      isServiceCall ? parameters['service_type'] as String? : null;
  Map<String, dynamic>? get request =>
      isServiceCall ? parameters['request'] as Map<String, dynamic>? : null;
  bool? get waitForResponse =>
      isServiceCall ? parameters['wait_for_response'] as bool? : null;
  String? get action => isActionGoal ? parameters['action'] as String? : null;
  String? get actionType =>
      isActionGoal ? parameters['action_type'] as String? : null;
  Map<String, dynamic>? get goal =>
      isActionGoal ? parameters['goal'] as Map<String, dynamic>? : null;
  bool? get waitForResult =>
      isActionGoal ? parameters['wait_for_result'] as bool? : null;
}

// Example usage:
/*
final mission = Mission(
  missionName: "warehouse_patrol",
  items: [
    MissionItem(
      id: "wp1",
      type: MissionItemType.goto,
      position: Position(x: 1.2, y: 3.4, theta: 0.0),
      name: "wp1",
    ),
  ],
);

// Convert to JSON
final jsonString = mission.toJsonString();

// Parse from JSON
final parsedMission = Mission.fromJsonString(jsonString);
*/
