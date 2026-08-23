import 'package:nav2_mission_planner/modals/bookmark.dart';

/// NavProMini robot configuration — always applied for this deployment.
class DefaultSettings {
  // Teleop Settings
  static const String cmdVelTopic = '/cmd_vel_teleop';
  static const double defaultLinearVelocity = 0.15;
  static const double defaultAngularVelocity = 0.45;
  static const double velocityStep = 0.05;
  static const String defaultTwistType = 'geometry_msgs/msg/Twist';

  static const List<String> availableTwistTypes = [
    'geometry_msgs/msg/Twist',
    'geometry_msgs/msg/TwistStamped'
  ];

  static const double minVelocity = 0.0;
  static const double maxVelocity = 100.0;

  // Mapping / Navigation — NavProMini wrappers
  static const String defaultMapsFolder = 'navpromini_mapping/maps';
  static const String defaultMappingLaunchFile =
      'navpromini_mission_planner/mapping_launch';
  static const String defaultMappingOdomTopic = '/odom';
  static const String defaultMappingOdomTopicType = 'nav_msgs/msg/Odometry';
  static const String defaultNavigationLaunchFile =
      'navpromini_mission_planner/navigation_launch';
  static const String defaultNavigationOdomTopic = '/amcl_pose';
  static const String defaultNavigationOdomTopicType =
      'geometry_msgs/msg/PoseWithCovarianceStamped';

  static const String defaultCameraTopic = '';

  static const String defaultOdomTopic = '/odom';
  static const String defaultOdomTopicType = 'nav_msgs/msg/Odometry';
  static const String defaultLidarTopic = '/scan';

  static const defaultSaveMapLaunchFile = 'nav2_mission_planner/save_map';

  static const bool defaultCameraVisible = false;
  static const bool defaultJoystickVisible = true;
  // Off by default: it is a diagnostic readout, and the map view is the
  // point of this screen. Anyone who needs exact numbers turns it on.
  static const bool defaultTelemetryVisible = true;

  static const String defaultPathTopic = '/plan';

  static const String defaultTfTopic = '/tf';
  static const String defaultMapFrame = 'map';
  static const String defaultOdomFrame = 'odom';
  static const String defaultBaseLinkFrame = 'base_link';

  static const Map<String, List<Bookmark>> defaultBookmarks = {};

  static const bool defaultBookmarksVisible = true;

  static const int defaultCommunicationTimeout = 120;

  static const List<Map<String, String>> defaultMappingArgs = [
    {'name': 'use_sim_time', 'value': 'false'},
  ];

  static const List<Map<String, String>> defaultNavigationArgs = [
    {'name': 'use_sim_time', 'value': 'false'},
  ];
}
