import 'package:flutter/material.dart';

import 'browser_frame_stub.dart'
    if (dart.library.html) 'browser_frame_web.dart';

/// Renders an embedded web browser frame across platforms.
/// On Flutter Web / WebKit (including the robot touchscreen WebKit runner),
/// this uses a hardware-accelerated sandboxed iframe without URL navigation bars.
/// On desktop environments without webview C++ bindings, it shows an interactive preview card.
Widget buildBrowserFrame(String url) {
  return buildPlatformBrowserFrame(url);
}
