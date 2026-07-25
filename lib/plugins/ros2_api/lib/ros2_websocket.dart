import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';

enum Status { none, connecting, connected, closed, errored }

class Ros2 {
  Ros2({this.url}) {
    _statusController = StreamController<Status>.broadcast();
    stream = const Stream.empty();
  }

  dynamic url;
  WebSocketChannel? _channel;
  StreamSubscription? _channelListener;
  late Stream<Map<String, dynamic>> stream;
  late StreamController<Status> _statusController;
  Status status = Status.none;
  int _callerId = 0;

  Stream<Status> get statusStream => _statusController.stream;

  /// Cross-platform connect (works on Flutter web + desktop/mobile).
  void connect({dynamic url}) {
    this.url = url ?? this.url;
    status = Status.connecting;
    _statusController.add(status);

    try {
      final uri = Uri.parse(this.url.toString());
      // WebSocketChannel.connect uses HtmlWebSocketChannel on web,
      // IOWebSocketChannel elsewhere — do NOT import web_socket_channel/io.dart.
      _channel = WebSocketChannel.connect(uri);
      stream = _channel!.stream.asBroadcastStream().map((raw) {
        if (raw is String) {
          return Map<String, dynamic>.from(json.decode(raw) as Map);
        }
        return Map<String, dynamic>.from(raw as Map);
      });

      status = Status.connected;
      _statusController.add(status);

      _channelListener = stream.listen((_) {}, onError: (error) {
        status = Status.errored;
        _statusController.add(status);
      }, onDone: () {
        status = Status.closed;
        _statusController.add(status);
      });
    } catch (e) {
      status = Status.errored;
      _statusController.add(status);
      rethrow;
    }
  }

  Future<void> close([int? code, String? reason]) async {
    await _channelListener?.cancel();
    _channelListener = null;
    try {
      await _channel?.sink.close(code, reason);
    } catch (_) {}
    _channel = null;
    status = Status.closed;
    _statusController.add(Status.closed);
  }

  bool send(dynamic message) {
    if (status != Status.connected || _channel == null) return false;
    final toSend =
        (message is Map || message is List) ? json.encode(message) : message;
    _channel!.sink.add(toSend);
    return true;
  }

  String requestServiceCaller(String serviceName) {
    return 'service_request:$serviceName:${_callerId++}';
  }

  String requestActionCaller(String actionName) {
    return const Uuid().v4();
  }
}
