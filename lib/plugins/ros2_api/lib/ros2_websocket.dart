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

  /// Messages sent while [status] is [Status.connecting] — see [send]'s own
  /// doc for why these are queued rather than dropped.
  final List<dynamic> _pending = [];

  Stream<Status> get statusStream => _statusController.stream;

  /// Cross-platform connect (works on Flutter web + desktop/mobile).
  void connect({dynamic url}) {
    this.url = url ?? this.url;
    status = Status.connecting;
    _statusController.add(status);
    _pending.clear(); // any previous attempt's queued sends are dead now

    try {
      final uri = Uri.parse(this.url.toString());
      // WebSocketChannel.connect uses HtmlWebSocketChannel on web,
      // IOWebSocketChannel elsewhere — do NOT import web_socket_channel/io.dart.
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      stream = channel.stream.asBroadcastStream().map((raw) {
        if (raw is String) {
          return Map<String, dynamic>.from(json.decode(raw) as Map);
        }
        return Map<String, dynamic>.from(raw as Map);
      });

      _channelListener = stream.listen((_) {}, onError: (error) {
        status = Status.errored;
        _statusController.add(status);
      }, onDone: () {
        status = Status.closed;
        _statusController.add(status);
      });

      // WebSocketChannel.connect() returns immediately — the real
      // handshake runs in the background, and `ready` is what actually
      // completes once it succeeds or fails. Reporting Status.connected
      // synchronously right after connect() (as this used to) meant
      // `status` lied for however long the handshake genuinely took: any
      // send() issued in that window read status == connected and went
      // straight into a channel that wasn't actually open yet, and got
      // silently dropped (no caller in this app retries on a false
      // return from send() — Subscriber.subscribe() in particular is
      // fire-and-forget). Confirmed live: a screen that mounts and
      // subscribes immediately after a reconnect (Map View is pushed on
      // top of AppShell, so retrying from its "Connection Lost" screen
      // means navigating back into a *fresh* Map View, not resuming one
      // in place) could lose its very first /map subscription to exactly
      // this race — permanently, since /map only republishes on change,
      // not on a timer — while a screen whose mount happened to land a
      // little later, after the handshake had actually caught up, worked
      // fine. Waiting for `ready` tells the truth about when the channel
      // can actually be written to; see send()'s own queuing for the
      // other half of the fix — status alone isn't enough while callers
      // don't retry.
      channel.ready.then((_) {
        status = Status.connected;
        _statusController.add(status);
        final queued = List<dynamic>.from(_pending);
        _pending.clear();
        for (final message in queued) {
          _sendNow(message);
        }
      }).catchError((Object _) {
        status = Status.errored;
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
    _pending.clear();
    status = Status.closed;
    _statusController.add(Status.closed);
  }

  /// Queues while the handshake is still in flight ([Status.connecting])
  /// rather than dropping — see [connect]'s own doc on why silently
  /// failing here was a real, timing-dependent way to lose a subscription
  /// for good. Still returns `false` outright (nothing queued) when
  /// there's no connection attempt in progress at all — [Status.none],
  /// [Status.closed], [Status.errored] — same as before.
  bool send(dynamic message) {
    if (status == Status.connecting) {
      _pending.add(message);
      return true;
    }
    if (status != Status.connected || _channel == null) return false;
    return _sendNow(message);
  }

  bool _sendNow(dynamic message) {
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
