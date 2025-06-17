import 'dart:async';
import 'ros2_websocket.dart';
import 'package:ros2_msg_utils/ros2_msg_utils.dart';
import 'package:rosapi_msgs/srv.dart';

/// Service Client to call ROS2 services
class ServiceClient<
    T extends RosServiceMessage<Request, Response>,
    Request extends RosMessage<Request>,
    Response extends RosMessage<Response>> {
  ServiceClient({
    required this.ros2,
    required this.name,
    required this.type,
    required this.serviceType,
  });

  final Ros2 ros2;
  final String name;
  final String type;
  final T serviceType;
  StreamSubscription? _listener;

  /// Call the service with a request
  Future<Response> call(Request request) async {
    // Check if the service exists before calling
    if (name != '/rosapi/services') {
      if (!await serviceExists(ros2, name)) {
        throw Exception('Service $name does not exist.');
      }
    }

    final callId = ros2.requestServiceCaller(name);
    final completer = Completer<Response>();

    _listener = ros2.stream
        .where((message) => message['id'] == callId)
        .listen((Map<String, dynamic> message) {
      if (message['result'] == null) {
        completer.completeError(message['values']!);
      } else {
        completer.complete(serviceType.response
            .fromJson(message['values'] as Map<String, dynamic>));
      }
      _listener!.cancel();
    });

    ros2.send({
      "op": 'call_service',
      "id": callId,
      "service": name,
      "type": type,
      "args": request.toJson(),
    });

    return completer.future;
  }

  void dispose() {
    _listener?.cancel();
  }
}

/// Service Server to handle ROS2 service requests
class ServiceServer<
    T extends RosServiceMessage<Request, Response>,
    Request extends RosMessage<Request>,
    Response extends RosMessage<Response>> {
  ServiceServer({
    required this.ros2,
    required this.name,
    required this.type,
    required this.serviceType,
  });

  final Ros2 ros2;
  final String name;
  final String type;
  final T serviceType;
  StreamSubscription? _subscription;

  bool get isAdvertised => _subscription != null;

  /// Start the service server with a handler function
  Future<void> serve(Future<Response> Function(Request) handler) async {
    if (isAdvertised) return;

    ros2.send({
      "op": 'advertise_service',
      "type": type,
      "service": name,
    });

    _subscription = ros2.stream.listen((Map<String, dynamic> message) async {
      if (message['service'] != name) return;

      try {
        final request = serviceType.request
            .fromJson(message['args'] as Map<String, dynamic>);

        final response = await handler(request);

        ros2.send({
          "op": 'service_response',
          "id": message['id'],
          "service": name,
          "values": response.toJson(),
          "result": true,
        });
      } catch (e) {
        ros2.send({
          "op": 'service_response',
          "id": message['id'],
          "service": name,
          "values": {'error': e.toString()},
          "result": false,
        });
      }
    });
  }

  void close() {
    if (!isAdvertised) return;
    ros2.send({
      "op": 'unadvertise_service',
      "service": name,
    });
    _subscription?.cancel();
    _subscription = null;
  }
}

Future<bool> serviceExists(Ros2 ros2, String serviceName) async {
  final servicesClient =
      ServiceClient<Services, ServicesRequest, ServicesResponse>(
          ros2: ros2,
          name: '/rosapi/services',
          type: Services().fullType,
          serviceType: Services());

  try {
    final request = ServicesRequest();
    final response = await servicesClient.call(request);
    return response.services.contains(serviceName);
  } catch (e) {
    return false;
  } finally {
    servicesClient.dispose();
  }
}

/// Example usage:
/// ```dart
/// // Service client usage
/// final client = ServiceClient<AddTwoInts, AddTwoIntsRequest, AddTwoIntsResponse>(
///   ros2: ros2Client,
///   name: '/add_two_ints',
///   type: 'example_interfaces/AddTwoInts',
///   serviceType: AddTwoInts(),
/// );
/// final request = AddTwoIntsRequest()..a = 2..b = 3;
/// final response = await client.call(request);
/// client.dispose();
///
/// // Service server usage
/// final server = ServiceServer<AddTwoInts, AddTwoIntsRequest, AddTwoIntsResponse>(
///   ros2: ros2Client,
///   name: '/add_two_ints',
///   type: 'example_interfaces/AddTwoInts',
///   serviceType: AddTwoInts(),
/// );
/// await server.serve((request) async {
///   return AddTwoIntsResponse()..sum = request.a + request.b;
/// });
/// server.close();
/// ```
