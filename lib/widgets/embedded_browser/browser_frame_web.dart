// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

final Set<String> _registeredViewTypes = {};

Widget buildPlatformBrowserFrame(String url) {
  final cleanUrl = url.trim();
  final viewType = 'embedded-browser-frame-${cleanUrl.hashCode.abs()}';

  if (!_registeredViewTypes.contains(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(
      viewType,
      (int viewId) {
        final iframe = html.IFrameElement()
          ..src = cleanUrl
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.backgroundColor = 'transparent'
          ..allow = 'autoplay; camera; microphone; geolocation'
          ..allowFullscreen = true;
        return iframe;
      },
    );
    _registeredViewTypes.add(viewType);
  }

  return HtmlElementView(viewType: viewType);
}
