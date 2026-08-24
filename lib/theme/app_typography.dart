import 'package:flutter/material.dart';

/// Material 3 type scale for the redesigned visual system, replacing the
/// two ad hoc styles previously on `AppTheme` (`statusTextStyle`,
/// `titleTextStyle`). Sizes/weights only — no color here; [AppTheme]
/// merges this onto `Typography.material2021(colorScheme: ...)` so text
/// still inherits the right on-surface color per theme brightness.
class AppTypography {
  AppTypography._();

  static const String? fontFamily = null; // system default for now

  static const TextTheme textTheme = TextTheme(
    displayLarge: TextStyle(
        fontSize: 57, fontWeight: FontWeight.w400, letterSpacing: -0.25),
    displayMedium: TextStyle(fontSize: 45, fontWeight: FontWeight.w400),
    displaySmall: TextStyle(fontSize: 36, fontWeight: FontWeight.w400),
    headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
    headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
    headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
    titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
    titleMedium: TextStyle(
        fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.15),
    titleSmall: TextStyle(
        fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1),
    bodyLarge: TextStyle(
        fontSize: 16, fontWeight: FontWeight.w400, letterSpacing: 0.5),
    bodyMedium: TextStyle(
        fontSize: 14, fontWeight: FontWeight.w400, letterSpacing: 0.25),
    bodySmall: TextStyle(
        fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: 0.4),
    labelLarge: TextStyle(
        fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1),
    labelMedium: TextStyle(
        fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5),
    labelSmall: TextStyle(
        fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5),
  );
}
