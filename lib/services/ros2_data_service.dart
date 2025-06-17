import 'package:nav2_mission_planner/providers/ros2_data_provider.dart';

/// A service class that wraps the ROS2DataProvider to maintain backward compatibility
/// with existing code that uses the TopicService and ServiceActionService classes.
class ROS2DataService {
  final ROS2DataProvider _provider;

  ROS2DataService(this._provider);

  // Topic Service methods
  Future<Map<String, String>> fetchTopics() async {
    await _provider.fetchTopics();
    return _provider.topics;
  }

  Future<Map<String, dynamic>> getMessageStructure(String messageType) async {
    // We need to pass a dummy topic name since the provider requires it
    // but the original implementation didn't
    return await _provider.getMessageStructure('dummy_topic', messageType);
  }

  // Service Action Service methods
  Future<Map<String, String>> fetchServices({bool forceRefresh = false}) async {
    await _provider.fetchServices(forceRefresh: forceRefresh);
    return _provider.services;
  }

  Future<List<String>> fetchActionServers({bool forceRefresh = false}) async {
    await _provider.fetchActionServers(forceRefresh: forceRefresh);
    return _provider.actionServers;
  }

  Future<Map<String, dynamic>> getServiceRequestStructure(String serviceType,
      {bool forceRefresh = false}) async {
    // We need to pass a dummy service name since the provider requires it
    // but the original implementation didn't
    return await _provider.getServiceRequestStructure(
        'dummy_service', serviceType);
  }

  Future<Map<String, dynamic>> getServiceResponseStructure(String serviceType,
      {bool forceRefresh = false}) async {
    // We need to pass a dummy service name since the provider requires it
    // but the original implementation didn't
    return await _provider.getServiceResponseStructure(
        'dummy_service', serviceType);
  }

  Future<Map<String, dynamic>> getActionGoalStructure(String actionType,
      {bool forceRefresh = false}) async {
    // We need to pass a dummy action name since the provider requires it
    // but the original implementation didn't
    return await _provider.getActionGoalStructure('dummy_action', actionType);
  }

  Future<String> getServiceType(String serviceName) async {
    return await _provider.getServiceType(serviceName);
  }

  Future<String> getActionType(String actionName) async {
    return await _provider.getActionType(actionName);
  }
}
