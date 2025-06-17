import 'package:ros2_api/ros2_api.dart';
import 'package:rosapi_msgs/srv.dart';
import 'package:nav2_mission_planner/providers/connection_provider.dart';
import 'package:nav2_mission_planner/providers/ros2_data_provider.dart';
import 'package:nav2_mission_planner/services/message_parser.dart';
import 'dart:developer' as developer;

class ServiceActionService {
  final ConnectionProvider _connectionProvider;
  final ROS2DataProvider _ros2DataProvider;

  ServiceActionService(this._connectionProvider, this._ros2DataProvider);

  // Constructor for backward compatibility
  factory ServiceActionService.fromConnectionProvider(
      ConnectionProvider connectionProvider) {
    // This should only be used in tests or when ROS2DataProvider is not available
    throw UnimplementedError(
        'ServiceActionService requires ROS2DataProvider. Use the primary constructor.');
  }

  Future<Map<String, String>> fetchServices({bool forceRefresh = false}) async {
    developer.log(
        '[ServiceActionService] Fetching services list with types using ROS2DataProvider...');
    try {
      await _ros2DataProvider.fetchServices(forceRefresh: forceRefresh);
      developer.log(
          '[ServiceActionService] Found ${_ros2DataProvider.services.length} services with types');
      return _ros2DataProvider.services;
    } catch (e) {
      developer.log('[ServiceActionService] Error fetching services: $e',
          error: e, stackTrace: StackTrace.current);
      rethrow;
    }
  }

  Future<List<String>> fetchActionServers({bool forceRefresh = false}) async {
    try {
      await _ros2DataProvider.fetchActionServers(forceRefresh: forceRefresh);
      return _ros2DataProvider.actionServers;
    } catch (e) {
      throw Exception('Failed to fetch action servers: $e');
    }
  }

  Future<Map<String, dynamic>> getServiceRequestStructure(String serviceType,
      {bool forceRefresh = false}) async {
    developer.log(
        '[ServiceActionService] Getting request structure for: $serviceType using ROS2DataProvider');
    try {
      // We need to pass a dummy service name since the provider requires it
      // but the original implementation didn't
      final structure = await _ros2DataProvider.getServiceRequestStructure(
          'dummy_service', serviceType);
      developer.log(
          '[ServiceActionService] Parsed request structure for $serviceType: $structure');
      return structure;
    } catch (e) {
      developer.log(
          '[ServiceActionService] Error parsing request structure for $serviceType: $e',
          error: e,
          stackTrace: StackTrace.current);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getServiceResponseStructure(String serviceType,
      {bool forceRefresh = false}) async {
    developer.log(
        '[ServiceActionService] Getting response structure for: $serviceType using ROS2DataProvider');
    try {
      // We need to pass a dummy service name since the provider requires it
      // but the original implementation didn't
      final structure = await _ros2DataProvider.getServiceResponseStructure(
          'dummy_service', serviceType);
      developer.log(
          '[ServiceActionService] Parsed response structure for $serviceType: $structure');
      return structure;
    } catch (e) {
      developer.log(
          '[ServiceActionService] Error parsing response structure for $serviceType: $e',
          error: e,
          stackTrace: StackTrace.current);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getActionGoalStructure(String actionType,
      {bool forceRefresh = false}) async {
    developer.log(
        '[ServiceActionService] Getting goal structure for: $actionType using ROS2DataProvider');
    try {
      // We need to pass a dummy action name since the provider requires it
      // but the original implementation didn't
      final structure = await _ros2DataProvider.getActionGoalStructure(
          'dummy_action', actionType);
      developer.log(
          '[ServiceActionService] Parsed goal structure for $actionType: $structure');
      return structure;
    } catch (e) {
      developer.log(
          '[ServiceActionService] Error parsing goal structure for $actionType: $e',
          error: e,
          stackTrace: StackTrace.current);
      rethrow;
    }
  }

  // New method to get service type when user selects a service
  Future<String> getServiceType(String serviceName) async {
    developer.log(
        '[ServiceActionService] Getting type for service: $serviceName using ROS2DataProvider');
    try {
      final serviceType = await _ros2DataProvider.getServiceType(serviceName);
      developer.log(
          '[ServiceActionService] Service type for $serviceName: $serviceType');
      return serviceType;
    } catch (e) {
      developer.log(
          '[ServiceActionService] Error getting type for $serviceName: $e',
          error: e,
          stackTrace: StackTrace.current);
      rethrow;
    }
  }

  Future<String> getActionType(String actionName) async {
    developer.log(
        '[ServiceActionService] Getting type for action: $actionName using ROS2DataProvider');
    try {
      final actionType = await _ros2DataProvider.getActionType(actionName);
      developer.log(
          '[ServiceActionService] Action type for $actionName: $actionType');
      return actionType;
    } catch (e) {
      developer.log(
          '[ServiceActionService] Error getting type for $actionName: $e',
          error: e,
          stackTrace: StackTrace.current);
      rethrow;
    }
  }
}
