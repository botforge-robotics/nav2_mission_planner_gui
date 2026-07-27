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
    displayName: 'GOTO',
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
  ),
  apiCall(
    displayName: 'API Call',
    icon: Icons.http,
    color: Colors.purple,
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

  // API CALL parameters
  String? apiUrl;
  String? apiMethod; // GET, POST, PUT, PATCH, DELETE
  Map<String, String>? apiHeaders;
  String? apiBody;
  bool? apiWaitForResponse;

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
    this.apiUrl,
    this.apiMethod,
    this.apiHeaders,
    this.apiBody,
    this.apiWaitForResponse,
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
      'apiUrl': apiUrl,
      'apiMethod': apiMethod,
      'apiHeaders': apiHeaders,
      'apiBody': apiBody,
      'apiWaitForResponse': apiWaitForResponse,
      'hasStructureWarning': hasStructureWarning,
    };
  }

  factory MissionItem.fromJson(Map<String, dynamic> json) {
    Map<String, String>? headers;
    if (json['apiHeaders'] is Map) {
      headers = (json['apiHeaders'] as Map).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    }

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
      apiUrl: json['apiUrl'],
      apiMethod: json['apiMethod'],
      apiHeaders: headers,
      apiBody: json['apiBody'],
      apiWaitForResponse: json['apiWaitForResponse'],
      hasStructureWarning: json['hasStructureWarning'] ?? false,
    );
  }

  /// Returns a descriptive subtitle for this item
  String get subtitle {
    switch (type) {
      case MissionItemType.goto:
        if (position != null) {
          // If name starts with "Waypoint ", "Circle_", "Spiral_", or "Zigzag_" it's a position from map, show coordinates
          if (name != null &&
              (name!.startsWith('Waypoint ') ||
                  name!.startsWith('Circle_') ||
                  name!.startsWith('Spiral_') ||
                  name!.startsWith('Zigzag_'))) {
            return 'X: ${position!.x.toStringAsFixed(2)}, Y: ${position!.y.toStringAsFixed(2)}, θ: ${position!.theta.toStringAsFixed(2)}';
          } else {
            // It's a bookmark, show "Bookmark"
            return 'Bookmark';
          }
        }
        return 'No position set';

      case MissionItemType.wait:
        return 'Wait for specified time';

      case MissionItemType.publish:
        String details = '';
        if (publishTopic != null) {
          details += 'Publish Topic';
        }
        if (publishMsgType != null) {
          details += details.isNotEmpty
              ? ' • Type: $publishMsgType'
              : 'Type: $publishMsgType';
        }
        return details.isEmpty ? 'No topic set' : details;

      case MissionItemType.callService:
        String details = '';
        if (serviceName != null) {
          details += 'Call Service';
        }
        if (waitForServiceResponse == true) {
          details +=
              details.isNotEmpty ? ' • Wait for response' : 'Wait for response';
        }
        return details.isEmpty ? 'No service set' : details;

      case MissionItemType.callAction:
        String details = '';
        if (actionName != null) {
          details += 'Send Action';
        }
        if (waitForActionResult == true) {
          details +=
              details.isNotEmpty ? ' • Wait for result' : 'Wait for result';
        }
        return details.isEmpty ? 'No action set' : details;

      case MissionItemType.captureImage:
        return 'Capture and save camera image';

      case MissionItemType.apiCall:
        String details = '';
        if (apiMethod != null) {
          details += apiMethod!;
        }
        if (apiUrl != null && apiUrl!.isNotEmpty) {
          details += details.isNotEmpty ? ' • $apiUrl' : apiUrl!;
        }
        if (apiWaitForResponse == true) {
          details +=
              details.isNotEmpty ? ' • Wait for response' : 'Wait for response';
        }
        return details.isEmpty ? 'No URL set' : details;
    }
  }

  String get displayTitle {
    switch (type) {
      case MissionItemType.goto:
        // If name starts with "Waypoint", "Circle_", "Spiral_", or "Zigzag_" it's a position from map, otherwise it's a bookmark
        if (name != null &&
            (name!.startsWith('Waypoint') ||
                name!.startsWith('Circle_') ||
                name!.startsWith('Spiral_') ||
                name!.startsWith('Zigzag_'))) {
          return name!;
        } else {
          // For bookmarks, return the bookmark name
          return name ?? 'Position';
        }

      case MissionItemType.wait:
        return '${waitDuration?.toStringAsFixed(1) ?? '0'}s';

      case MissionItemType.publish:
        String title = publishTopic ?? 'Publish';
        if (publishFrequencyType == 'hz' && publishFrequency != null) {
          title += ' • ${publishFrequency}Hz';
        } else if (publishFrequencyType == 'duration' &&
            publishDuration != null) {
          title += ' • ${publishDuration}s';
        } else if (publishFrequencyType == 'once') {
          title += ' • Once';
        }
        return title;

      case MissionItemType.callService:
        return serviceName ?? 'Service Call';

      case MissionItemType.callAction:
        return actionName ?? 'Action Call';

      case MissionItemType.captureImage:
        return 'Capture Image';

      case MissionItemType.apiCall:
        final method = apiMethod ?? 'POST';
        final url = apiUrl;
        if (url != null && url.isNotEmpty) {
          return '$method $url';
        }
        return 'API Call';
    }
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
