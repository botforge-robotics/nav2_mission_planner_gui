import 'package:flutter/material.dart';
import 'package:nav2_mission_planner/providers/connection_provider.dart';
import 'package:nav2_mission_planner/providers/settings_provider.dart';
import 'package:nav2_mission_planner/services/message_parser.dart';
import 'dart:async';
import 'package:rosapi_msgs/srv.dart';
import 'package:ros2_api/ros2_api.dart';

class ROS2DataProvider extends ChangeNotifier {
  final ConnectionProvider _connectionProvider;
  final SettingsProvider _settingsProvider;

  // Data storage
  Map<String, String> _topics = {};
  Map<String, String> _services = {};
  List<String> _actionServers = [];
  Map<String, Map<String, dynamic>> _messageStructures = {};

  // Loading states
  bool _isLoadingTopics = false;
  bool _isLoadingServices = false;
  bool _isLoadingActions = false;
  bool _isLoadingMessageStructure = false;

  // Getters
  Map<String, String> get topics => _topics;
  Map<String, String> get services => _services;
  List<String> get actionServers => _actionServers;
  Map<String, Map<String, dynamic>> get messageStructures => _messageStructures;

  bool get isLoadingTopics => _isLoadingTopics;
  bool get isLoadingServices => _isLoadingServices;
  bool get isLoadingActions => _isLoadingActions;
  bool get isLoadingMessageStructure => _isLoadingMessageStructure;
  bool get isLoading =>
      _isLoadingTopics ||
      _isLoadingServices ||
      _isLoadingActions ||
      _isLoadingMessageStructure;

  ROS2DataProvider(this._connectionProvider, this._settingsProvider);

  Duration get _timeout =>
      Duration(seconds: _settingsProvider.communicationTimeout);

  // Check if ROS2 client is available
  bool get isConnected =>
      _connectionProvider.isConnected && _connectionProvider.ros2Client != null;

  // Get ROS2 client
  get ros2 => _connectionProvider.ros2Client;

  // Fetch topics and their types
  Future<void> fetchTopics({bool forceRefresh = false}) async {
    if (!isConnected) return;
    if (!forceRefresh && _topics.isNotEmpty) return;

    try {
      _isLoadingTopics = true;
      notifyListeners();

      final client = ServiceClient<Topics, TopicsRequest, TopicsResponse>(
        ros2: ros2,
        name: '/rosapi/topics',
        type: Topics().fullType,
        serviceType: Topics(),
        timeout: _timeout.inSeconds.toDouble(),
      );

      final response = await client.call(TopicsRequest());
      final topicMap = <String, String>{};

      for (final topic in response.topics) {
        try {
          final typeClient =
              ServiceClient<TopicType, TopicTypeRequest, TopicTypeResponse>(
            ros2: ros2,
            name: '/rosapi/topic_type',
            type: TopicType().fullType,
            serviceType: TopicType(),
            timeout: _timeout.inSeconds.toDouble(),
          );

          final typeResponse =
              await typeClient.call(TopicTypeRequest(topic: topic));
          if (typeResponse.type.isNotEmpty) {
            topicMap[topic] = typeResponse.type;
          }
        } catch (e) {
          // Silent error handling
        }
      }

      _topics = topicMap;
    } catch (e) {
      // Silent error handling
    } finally {
      _isLoadingTopics = false;
      notifyListeners();
    }
  }

  // Fetch services and their types
  Future<void> fetchServices({bool forceRefresh = false}) async {
    if (!isConnected) return;
    if (!forceRefresh && _services.isNotEmpty) return;

    try {
      _isLoadingServices = true;
      notifyListeners();

      final client = ServiceClient<Services, ServicesRequest, ServicesResponse>(
        ros2: ros2,
        name: '/rosapi/services',
        type: Services().fullType,
        serviceType: Services(),
        timeout: _timeout.inSeconds.toDouble(),
      );

      final response = await client.call(ServicesRequest());
      final serviceMap = <String, String>{};

      for (final service in response.services) {
        try {
          final typeClient = ServiceClient<ServiceType, ServiceTypeRequest,
              ServiceTypeResponse>(
            ros2: ros2,
            name: '/rosapi/service_type',
            type: ServiceType().fullType,
            serviceType: ServiceType(),
            timeout: _timeout.inSeconds.toDouble(),
          );

          final typeResponse =
              await typeClient.call(ServiceTypeRequest(service: service));
          serviceMap[service] = typeResponse.type;
        } catch (e) {
          print(
              '[ROS2DataProvider] Error getting type for service $service: $e');
          serviceMap[service] = 'unknown';
        }
      }

      _services = serviceMap;
    } catch (e) {
      // Silent error handling
    } finally {
      _isLoadingServices = false;
      notifyListeners();
    }
  }

  // Fetch action servers
  Future<void> fetchActionServers({bool forceRefresh = false}) async {
    if (!isConnected) return;
    if (!forceRefresh && _actionServers.isNotEmpty) return;

    try {
      _isLoadingActions = true;
      notifyListeners();

      final client = ServiceClient<GetActionServers, GetActionServersRequest,
          GetActionServersResponse>(
        ros2: ros2,
        name: '/rosapi/action_servers',
        type: GetActionServers().fullType,
        serviceType: GetActionServers(),
        timeout: _timeout.inSeconds.toDouble(),
      );

      final response = await client.call(GetActionServersRequest());
      _actionServers = response.action_servers;
    } catch (e) {
      // Silent error handling
    } finally {
      _isLoadingActions = false;
      notifyListeners();
    }
  }

  // Get message structure for a topic
  Future<Map<String, dynamic>> getMessageStructure(
      String topicName, String messageType) async {
    if (!isConnected) return {};

    final normalizedType = MessageParser.normalizeMessageType(messageType);
    if (_messageStructures.containsKey(normalizedType)) {
      return _messageStructures[normalizedType]!;
    }

    try {
      _isLoadingMessageStructure = true;
      notifyListeners();

      final client = ServiceClient<MessageDetails, MessageDetailsRequest,
          MessageDetailsResponse>(
        ros2: ros2,
        name: '/rosapi/message_details',
        type: MessageDetails().fullType,
        serviceType: MessageDetails(),
        timeout: _timeout.inSeconds.toDouble(),
      );

      final response =
          await client.call(MessageDetailsRequest(type: messageType));
      final structure = MessageParser.parseMessageStructure(
          response.typedefs, messageType, 'msg');

      _messageStructures[normalizedType] = structure;
      return structure;
    } catch (e) {
      return {};
    } finally {
      _isLoadingMessageStructure = false;
      notifyListeners();
    }
  }

  // Get service request structure
  Future<Map<String, dynamic>> getServiceRequestStructure(
      String serviceName, String serviceType) async {
    if (!isConnected) return {};

    final key = '${serviceType}_request';
    if (_messageStructures.containsKey(key)) {
      return _messageStructures[key]!;
    }

    try {
      _isLoadingMessageStructure = true;
      notifyListeners();

      final client = ServiceClient<ServiceRequestDetails,
          ServiceRequestDetailsRequest, ServiceRequestDetailsResponse>(
        ros2: ros2,
        name: '/rosapi/service_request_details',
        type: ServiceRequestDetails().fullType,
        serviceType: ServiceRequestDetails(),
        timeout: _timeout.inSeconds.toDouble(),
      );

      final response =
          await client.call(ServiceRequestDetailsRequest(type: serviceType));
      final structure = MessageParser.parseMessageStructure(
          response.typedefs, serviceType, 'srv');

      _messageStructures[key] = structure;
      return structure;
    } catch (e) {
      return {};
    } finally {
      _isLoadingMessageStructure = false;
      notifyListeners();
    }
  }

  // Get service response structure
  Future<Map<String, dynamic>> getServiceResponseStructure(
      String serviceName, String serviceType) async {
    if (!isConnected) return {};

    final key = '${serviceType}_response';
    if (_messageStructures.containsKey(key)) {
      return _messageStructures[key]!;
    }

    try {
      _isLoadingMessageStructure = true;
      notifyListeners();

      final client = ServiceClient<ServiceResponseDetails,
          ServiceResponseDetailsRequest, ServiceResponseDetailsResponse>(
        ros2: ros2,
        name: '/rosapi/service_response_details',
        type: ServiceResponseDetails().fullType,
        serviceType: ServiceResponseDetails(),
        timeout: _timeout.inSeconds.toDouble(),
      );

      final response =
          await client.call(ServiceResponseDetailsRequest(type: serviceType));
      final structure = MessageParser.parseMessageStructure(
          response.typedefs, serviceType, 'srv');

      _messageStructures[key] = structure;
      return structure;
    } catch (e) {
      return {};
    } finally {
      _isLoadingMessageStructure = false;
      notifyListeners();
    }
  }

  // Get action goal structure
  Future<Map<String, dynamic>> getActionGoalStructure(
      String actionName, String actionType) async {
    if (!isConnected) return {};

    final key = '${actionType}_goal';
    if (_messageStructures.containsKey(key)) {
      return _messageStructures[key]!;
    }

    try {
      _isLoadingMessageStructure = true;
      notifyListeners();

      final client = ServiceClient<ActionGoalDetails, ActionGoalDetailsRequest,
          ActionGoalDetailsResponse>(
        ros2: ros2,
        name: '/rosapi/action_goal_details',
        type: ActionGoalDetails().fullType,
        serviceType: ActionGoalDetails(),
        timeout: _timeout.inSeconds.toDouble(),
      );

      final response =
          await client.call(ActionGoalDetailsRequest(type: actionType));
      final structure = MessageParser.parseMessageStructure(
          response.typedefs, actionType, 'action');

      _messageStructures[key] = structure;
      return structure;
    } catch (e) {
      return {};
    } finally {
      _isLoadingMessageStructure = false;
      notifyListeners();
    }
  }

  // Get service type
  Future<String> getServiceType(String serviceName) async {
    if (!isConnected) return '';

    if (_services.containsKey(serviceName)) {
      return _services[serviceName]!;
    }

    try {
      final typeClient =
          ServiceClient<ServiceType, ServiceTypeRequest, ServiceTypeResponse>(
        ros2: ros2,
        name: '/rosapi/service_type',
        type: ServiceType().fullType,
        serviceType: ServiceType(),
        timeout: _timeout.inSeconds.toDouble(),
      );

      final typeResponse =
          await typeClient.call(ServiceTypeRequest(service: serviceName));
      _services[serviceName] = typeResponse.type;
      return typeResponse.type;
    } catch (e) {
      return '';
    }
  }

  // Get action type
  Future<String> getActionType(String actionName) async {
    if (!isConnected) return '';

    try {
      final typeClient =
          ServiceClient<ActionType, ActionTypeRequest, ActionTypeResponse>(
        ros2: ros2,
        name: '/rosapi/action_type',
        type: ActionType().fullType,
        serviceType: ActionType(),
        timeout: _timeout.inSeconds.toDouble(),
      );

      final typeResponse =
          await typeClient.call(ActionTypeRequest(action: actionName));
      return typeResponse.type;
    } catch (e) {
      return '';
    }
  }

  // Initialize all data
  Future<void> initializeAllData() async {
    if (!isConnected) return;

    await Future.wait([
      fetchTopics(),
      fetchServices(),
      fetchActionServers(),
    ]);
  }

  // Clear all cached data
  void clearCache() {
    _topics.clear();
    _services.clear();
    _actionServers.clear();
    _messageStructures.clear();
    notifyListeners();
  }
}
