import 'package:ros2_api/ros2_api.dart';
import 'package:rosapi_msgs/srv.dart';
import 'package:nav2_mission_planner/providers/connection_provider.dart';
import 'package:nav2_mission_planner/providers/ros2_data_provider.dart';
import 'package:nav2_mission_planner/services/message_parser.dart';

class TopicService {
  final ConnectionProvider _connectionProvider;
  final ROS2DataProvider _ros2DataProvider;

  Ros2 get ros2 => _connectionProvider.ros2Client!;

  TopicService(this._connectionProvider, this._ros2DataProvider);

  // Constructor for backward compatibility
  factory TopicService.fromConnectionProvider(
      ConnectionProvider connectionProvider) {
    // This should only be used in tests or when ROS2DataProvider is not available
    throw UnimplementedError(
        'TopicService requires ROS2DataProvider. Use the primary constructor.');
  }

  Future<Map<String, String>> fetchTopics() async {
    print('[TopicService] Starting topics fetch using ROS2DataProvider...');
    try {
      await _ros2DataProvider.fetchTopics();
      print(
          '[TopicService] Completed topics fetch with ${_ros2DataProvider.topics.length} valid entries');
      return _ros2DataProvider.topics;
    } catch (e) {
      print('[TopicService] Critical error in fetchTopics: $e');
      throw Exception('Failed to fetch topics: $e');
    }
  }

  Future<Map<String, dynamic>> getMessageStructure(String messageType) async {
    print(
        '[TopicService] Fetching message structure for $messageType using ROS2DataProvider');
    try {
      // We need to pass a dummy topic name since the provider requires it
      // but the original implementation didn't
      return await _ros2DataProvider.getMessageStructure(
          'dummy_topic', messageType);
    } catch (e) {
      print('[TopicService] Error fetching message structure: $e');
      throw Exception('Failed to get message structure: $e');
    }
  }
}
