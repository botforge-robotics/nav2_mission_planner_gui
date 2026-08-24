import 'package:flutter/material.dart';

/// Material 3 window-size-class breakpoints, used to adapt layouts (nav
/// rail width, panel-as-drawer vs panel-as-sidebar, grid column counts)
/// across the app's two very different runtime shapes:
///  - native mobile/tablet builds, which are landscape-locked end to end
///    (see `main.dart`'s `SystemChrome.setPreferredOrientations`), and
///  - the web build, which ignores that lock and runs in an arbitrarily
///    sized, resizable browser window (including narrow ones).
///
/// There was no prior art for this in the codebase — every existing layout
/// is a fixed-pixel Stack/Row/Column (e.g. `AppTheme.controlPanelWidth`,
/// the waypoint panel's fixed 300px width, the settings sidebar's fixed 18%
/// width) — so this is new infrastructure, not a token rename.
enum WindowSizeClass {
  /// <600dp width. Narrow web window; still needs to be usable even though
  /// native builds never actually run this narrow.
  compact,

  /// 600–840dp width. Phone-landscape / small-tablet-landscape.
  medium,

  /// 840–1200dp width. Tablet-landscape / small desktop window.
  expanded,

  /// 1200dp+ width. Desktop.
  large;

  static const double _mediumMin = 600;
  static const double _expandedMin = 840;
  static const double _largeMin = 1200;

  /// Resolves the window size class for the current [context] from its
  /// logical width (`MediaQuery.sizeOf(context).width`).
  static WindowSizeClass of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return fromWidth(width);
  }

  /// Resolves the window size class from a raw logical width, for call
  /// sites that already have a `LayoutBuilder` constraint rather than a
  /// `BuildContext` handy.
  static WindowSizeClass fromWidth(double width) {
    if (width >= _largeMin) return WindowSizeClass.large;
    if (width >= _expandedMin) return WindowSizeClass.expanded;
    if (width >= _mediumMin) return WindowSizeClass.medium;
    return WindowSizeClass.compact;
  }

  bool get isCompact => this == WindowSizeClass.compact;
  bool get isMediumOrWider =>
      this == WindowSizeClass.medium ||
      this == WindowSizeClass.expanded ||
      this == WindowSizeClass.large;
  bool get isExpandedOrWider =>
      this == WindowSizeClass.expanded || this == WindowSizeClass.large;
  bool get isLarge => this == WindowSizeClass.large;
}
