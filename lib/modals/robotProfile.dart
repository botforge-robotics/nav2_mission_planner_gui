class RobotProfile {
  final String id;
  String name;
  String ip;
  String port;
  final String settingsId; // Links to settings
  bool isConfigured; // Track if robot setup is complete

  RobotProfile({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.settingsId,
    this.isConfigured = false, // Default to not configured
  });

  factory RobotProfile.fromJson(Map<String, dynamic> json) => RobotProfile(
        id: json['id'],
        name: json['name'],
        ip: json['ip'],
        port: json['port'],
        settingsId: json['settingsId'],
        isConfigured: json['isConfigured'] ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'ip': ip,
        'port': port,
        'settingsId': settingsId,
        'isConfigured': isConfigured,
      };
}
