import 'package:flutter/material.dart';

/// Motion tokens for the whole app — one small vocabulary of durations and
/// curves, reused everywhere instead of each screen picking its own numbers.
/// Every curve here is intentionally non-bouncy (no elastic/overshoot
/// curves): this is an operator control surface, not a game, so motion
/// should read as *confident and settled*, never springy.
class AppMotion {
  AppMotion._();

  // -- durations -------------------------------------------------------------

  /// Button/tap press feedback, icon swaps — barely perceptible as a
  /// duration, just enough to not be a hard cut.
  static const instant = Duration(milliseconds: 100);

  /// Small state changes: a value updating, a chip changing color, a row
  /// highlighting.
  static const fast = Duration(milliseconds: 180);

  /// The default: card entrances, content cross-fades, list item reveals.
  static const medium = Duration(milliseconds: 320);

  /// Page-level transitions, larger reveals (a whole screen's content
  /// settling in after a connection resolves).
  static const slow = Duration(milliseconds: 480);

  /// One full cycle of a "breathing" status indicator (StatusPulseDot).
  /// Slow and even on purpose — a pulse that communicates "this is live"
  /// should sit in the background of attention, not compete for it.
  static const pulseCycle = Duration(milliseconds: 1600);

  // -- curves ------------------------------------------------------------

  /// Entrances — content arriving on screen.
  static const enter = Curves.easeOutCubic;

  /// Exits — content leaving.
  static const exit = Curves.easeInCubic;

  /// State-to-state transitions where both ends matter (a value tweening
  /// from A to B, a page transition). Flutter's built-in "emphasized" curve:
  /// smooth acceleration and deceleration with no overshoot.
  static const settle = Curves.easeInOutCubicEmphasized;

  /// The breathing curve for pulse animations — symmetric ease, so the
  /// pulse feels like a steady heartbeat rather than a mechanical blink.
  static const breathe = Curves.easeInOut;

  // -- page transitions ----------------------------------------------------

  /// Fade + a small upward settle, no slide-from-edge and no bounce —
  /// applied globally via ThemeData.pageTransitionsTheme, so every existing
  /// `Navigator.push(MaterialPageRoute(...))` call site gets it for free.
  static const pageTransitionsTheme = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: _SettledPageTransitionsBuilder(),
      TargetPlatform.iOS: _SettledPageTransitionsBuilder(),
      TargetPlatform.macOS: _SettledPageTransitionsBuilder(),
      TargetPlatform.linux: _SettledPageTransitionsBuilder(),
      TargetPlatform.windows: _SettledPageTransitionsBuilder(),
      TargetPlatform.fuchsia: _SettledPageTransitionsBuilder(),
    },
  );
}

class _SettledPageTransitionsBuilder extends PageTransitionsBuilder {
  const _SettledPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.settle,
        reverseCurve: AppMotion.exit);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
            .animate(curved),
        child: child,
      ),
    );
  }
}
