import 'dart:async';

import 'package:ros2_api/ros2_api.dart';

/// Opens a Ros2 connection and confirms it's genuinely alive, closing it
/// again afterward — used by both Splash (silent reconnect check) and
/// Setup: Robot (first-time connect), so there's one place that understands
/// Ros2.connect()'s optimistic status semantics.
///
/// Ros2.connect() marks itself "connected" as soon as the platform
/// WebSocket channel object is created, before the handshake actually
/// finishes — an errored/closed status arriving shortly after is the real
/// failure signal on that path. Fast-fails on that, otherwise waits out a
/// grace period and trusts "still connected, no error" as success.
Future<bool> probeRosbridge(
  String url, {
  Duration grace = const Duration(milliseconds: 700),
  Duration timeout = const Duration(seconds: 8),
}) async {
  final ros2 = Ros2(url: url);
  final completer = Completer<bool>();
  final sub = ros2.statusStream.listen((status) {
    if ((status == Status.errored || status == Status.closed) &&
        !completer.isCompleted) {
      completer.complete(false);
    }
  });

  try {
    ros2.connect();
  } catch (_) {
    if (!completer.isCompleted) completer.complete(false);
  }

  if (!completer.isCompleted) {
    await Future.delayed(grace);
    if (!completer.isCompleted) {
      completer.complete(ros2.status == Status.connected);
    }
  }

  final ok = await completer.future.timeout(timeout, onTimeout: () => false);
  await sub.cancel();
  await ros2.close();
  return ok;
}
