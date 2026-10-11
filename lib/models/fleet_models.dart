enum AppConnectionMode {
  directRobot,
  fleetServer,
}

class FleetRobotInfo {
  final String id;
  final String name;
  final String serial;
  final String status; // 'pending', 'active', 'retired'
  final String? fleet;
  final String? fleetId;
  final String? levelId;
  final String? levelName;
  final String? dockWaypoint;
  final String? homeWaypoint;
  final double? batteryPercent;
  final String? navMode; // 'HARDWARE', 'MAPPING', 'NAV_READY', 'NAV_ACTIVE'
  final bool isTaskReady;
  final double? x;
  final double? y;
  final double? yaw;
  final String? ip;
  final DateTime? lastSeen;

  const FleetRobotInfo({
    required this.id,
    required this.name,
    required this.serial,
    required this.status,
    this.fleet,
    this.fleetId,
    this.levelId,
    this.levelName,
    this.dockWaypoint,
    this.homeWaypoint,
    this.batteryPercent,
    this.navMode,
    this.isTaskReady = false,
    this.x,
    this.y,
    this.yaw,
    this.ip,
    this.lastSeen,
  });

  factory FleetRobotInfo.fromJson(Map<String, dynamic> json) {
    return FleetRobotInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? json['serial'] as String? ?? 'Unnamed Robot',
      serial: json['serial'] as String? ?? '',
      status: json['status'] as String? ?? 'unknown',
      fleet: json['fleet'] as String? ?? json['fleetName'] as String?,
      fleetId: json['fleetId'] as String?,
      levelId: json['levelId'] as String?,
      levelName: json['levelName'] as String?,
      dockWaypoint: json['dockWaypoint'] as String?,
      homeWaypoint: json['homeWaypoint'] as String?,
      batteryPercent: (json['battery'] as num?)?.toDouble() ??
          (json['batteryPercent'] as num?)?.toDouble() ??
          (json['state']?['battery'] as num?)?.toDouble(),
      navMode: json['navMode'] as String? ?? json['mode'] as String?,
      isTaskReady: json['isTaskReady'] == true || json['taskReady'] == true,
      x: (json['pose']?['x'] as num?)?.toDouble() ?? (json['x'] as num?)?.toDouble(),
      y: (json['pose']?['y'] as num?)?.toDouble() ?? (json['y'] as num?)?.toDouble(),
      yaw: (json['pose']?['yaw'] as num?)?.toDouble() ?? (json['yaw'] as num?)?.toDouble(),
      ip: json['ip'] as String?,
      lastSeen: json['lastSeen'] != null ? DateTime.tryParse(json['lastSeen'].toString()) : null,
    );
  }

  bool get isPending => status == 'pending';
  bool get isActive => status == 'active';
  bool get isCharging => navMode == 'CHARGING' || status == 'charging';
}

class FleetLevelInfo {
  final String id;
  final String name;
  final String buildingId;
  final String imageUrl;
  final double metersPerPixel;
  final double originX;
  final double originY;
  final double elevation;

  const FleetLevelInfo({
    required this.id,
    required this.name,
    required this.buildingId,
    required this.imageUrl,
    this.metersPerPixel = 0.05,
    this.originX = 0.0,
    this.originY = 0.0,
    this.elevation = 0.0,
  });

  factory FleetLevelInfo.fromJson(Map<String, dynamic> json) {
    return FleetLevelInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Floor',
      buildingId: json['buildingId'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      metersPerPixel: (json['metersPerPixel'] as num?)?.toDouble() ?? 0.05,
      originX: (json['originX'] as num?)?.toDouble() ?? 0.0,
      originY: (json['originY'] as num?)?.toDouble() ?? 0.0,
      elevation: (json['elevation'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class FleetInfo {
  final String id;
  final String name;
  final int robotCount;

  const FleetInfo({
    required this.id,
    required this.name,
    this.robotCount = 0,
  });

  factory FleetInfo.fromJson(Map<String, dynamic> json) {
    return FleetInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      robotCount: json['robotCount'] as int? ?? 0,
    );
  }
}
