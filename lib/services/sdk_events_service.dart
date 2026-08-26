import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// One entry from navpromini_sdk's `events` WS stream (handlers/events.py) —
/// a discrete occurrence (`navigation.completed`, `dock.failed`,
/// `battery.low`, ...), not a rate-limited telemetry sample. The SDK emits no
/// severity field, so it's derived here from the event name's own suffix —
/// real categorization of a real name, not an invented value.
class SdkEvent {
  const SdkEvent(
      {required this.name, required this.data, required this.receivedAt});

  final String name;
  final Map<String, dynamic> data;
  final DateTime receivedAt;

  SdkEventSeverity get severity {
    if (name.endsWith('.failed') ||
        name.endsWith('.error') ||
        name == 'localization.lost') {
      return SdkEventSeverity.critical;
    }
    if (name.endsWith('.low') ||
        name.endsWith('.lost') ||
        name.contains('slip')) {
      return SdkEventSeverity.warning;
    }
    return SdkEventSeverity.info;
  }

  String get message {
    final msg = data['message'];
    if (msg is String && msg.isNotEmpty) return msg;
    return name;
  }
}

enum SdkEventSeverity { critical, warning, info }

/// Connects to `/api/v1/events`, subscribes to the `events` stream only (not
/// the high-rate telemetry streams the same socket also offers — this app
/// gets pose/battery/velocity from rosbridge directly), and republishes
/// decoded [SdkEvent]s. Reconnects with backoff on drop; never throws to a
/// caller — same "optional enrichment" contract as [SdkApiService] and
/// [SdkStateService].
class SdkEventsService {
  SdkEventsService(this.robotIp, {this.port = 8090});

  final String robotIp;
  final int port;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  final _controller = StreamController<SdkEvent>.broadcast();
  bool _disposed = false;
  bool _connected = false;

  bool get isConnected => _connected;

  Stream<SdkEvent> get events => _controller.stream;

  /// Fires every time [isConnected] actually changes — this is the piece a
  /// caller needs for a "Live" indicator to be *correct*, not just
  /// eventually-correct: a widget that reads [isConnected] once at build
  /// time and never rebuilds again (nothing else prompting it — no event
  /// has arrived yet) would otherwise stay frozen on whatever the socket's
  /// state happened to be at that first build, even after it connects a
  /// moment later.
  final _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get connectionChanges => _connectionController.stream;

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    if (!_connectionController.isClosed) _connectionController.add(value);
  }

  void start() {
    if (_disposed) return;
    _connect();
  }

  void _connect() {
    _sub?.cancel();
    _channel?.sink.close();
    _setConnected(false);
    try {
      final uri = Uri.parse('ws://$robotIp:$port/api/v1/events');
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _sub = channel.stream.listen(
        _onMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
      channel.ready.then((_) {
        if (_disposed) return;
        _setConnected(true);
        channel.sink.add(jsonEncode({
          'action': 'subscribe',
          'streams': ['events'],
        }));
      }).catchError((_) => _scheduleReconnect());
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (msg['stream'] != 'events') return;
    final data = msg['data'] as Map<String, dynamic>?;
    if (data == null) return;
    final name = data['event'] as String?;
    if (name == null) return;
    _controller.add(SdkEvent(
      name: name,
      data: (data['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      receivedAt: DateTime.now(),
    ));
  }

  void _scheduleReconnect() {
    _setConnected(false);
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), _connect);
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _controller.close();
    _connectionController.close();
  }
}
