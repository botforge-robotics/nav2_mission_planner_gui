import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:uuid/uuid.dart';

enum Status { none, connecting, connected, closed, errored }

class Ros2 {
  Ros2({this.url}) {
    _statusController = StreamController<Status>.broadcast();
  }

  dynamic url;
  late WebSocketChannel _channel;
  late StreamSubscription _channelListener;
  late Stream<Map<String, dynamic>> stream;
  late StreamController<Status> _statusController;
  Status status = Status.none;
  int _callerId = 0;

  Stream<Status> get statusStream => _statusController.stream;

  void connect({dynamic url}) {
    this.url = url ?? this.url;

    try {
      _channel = IOWebSocketChannel.connect(Uri.parse(this.url));
      stream =
          _channel.stream.asBroadcastStream().map((raw) => json.decode(raw));

      status = Status.connected;
      _statusController.add(status);

      _channelListener = stream.listen((data) {}, onError: (error) {
        status = Status.errored;
        _statusController.add(status);
      }, onDone: () {
        status = Status.closed;
        _statusController.add(status);
      });
    } catch (e) {
      status = Status.errored;
      _statusController.add(status);
    }
  }

  Future<void> close([int? code, String? reason]) async {
    await _channelListener.cancel();
    await _channel.sink.close(code, reason);
    _statusController.add(Status.closed);
    status = Status.closed;
  }

  bool send(dynamic message) {
    if (status != Status.connected) return false;
    final toSend =
        (message is Map || message is List) ? json.encode(message) : message;

    _channel.sink.add(toSend);
    return true;
  }

  /// Generate a unique ID for service calls
  String requestServiceCaller(String serviceName) {
    return 'service_request:$serviceName:${_callerId++}';
  }

  /// Generate a unique ID for action calls
  String requestActionCaller(String actionName) {
    return const Uuid().v4();
  }
}
