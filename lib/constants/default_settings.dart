import 'package:nav2_mission_planner/modals/bookmark.dart';

class DefaultSettings {
  // Teleop Settings
  static const String cmdVelTopic = '/cmd_vel';
  static const double defaultLinearVelocity = 1.0;
  static const double defaultAngularVelocity = 1.0;
  static const double velocityStep = 0.05;
  static const String defaultTwistType = 'geometry_msgs/msg/Twist';

  // Available twist message types
  static const List<String> availableTwistTypes = [
    'geometry_msgs/msg/Twist',
    'geometry_msgs/msg/TwistStamped'
  ];

  // Min-Max values
  static const double minVelocity = 0.0;
  static const double maxVelocity = 100.0;

  // Mapping Settings

  static const String defaultMapsFolder = 'turtlebot4_navigation/maps';
  static const String defaultMappingLaunchFile = 'turtlebot4_navigation/slam';
  static const String defaultMappingOdomTopic = '/odom';
  static const String defaultMappingOdomTopicType = 'nav_msgs/msg/Odometry';
  // Navigation Settings
  static const String defaultNavigationLaunchFile =
      'turtlebot4_navigation/navigation';
  static const String defaultNavigationOdomTopic = '/amcl_pose';
  static const String defaultNavigationOdomTopicType =
      'geometry_msgs/msg/PoseWithCovarianceStamped';
  // Camera Topics
  static const String defaultCameraTopic = '';

  // Add new defaults
  static const String defaultOdomTopic = '/odom';
  static const String defaultOdomTopicType = 'nav_msgs/msg/Odometry';
  static const String defaultLidarTopic = '/scan';

  static const defaultSaveMapLaunchFile = 'rio_mapping/save_map';

  // Add these new constants
  static const bool defaultCameraVisible = true;
  static const bool defaultJoystickVisible = true;

  // Add new default path topic
  static const String defaultPathTopic = '/plan';

  static const Map<String, List<Bookmark>> defaultBookmarks = {};

  static const bool defaultBookmarksVisible = true;

  // Add default communication timeout in seconds
  static const int defaultCommunicationTimeout = 120;
}
