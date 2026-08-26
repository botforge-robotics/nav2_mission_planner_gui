import 'package:flutter/material.dart';

import 'app_motion.dart';

/// Design tokens for the NavPro Mini app — a premium autonomous-robotics
/// control surface. Primary is the robot's own body color (see
/// AppColors.primary), teal stays as the accent — developed into a full
/// layered-surface system: distinct elevation tiers, a tinted shadow
/// instead of a flat black one, and a restrained set of gradients reserved
/// for the handful of places that earn one (the robot avatar, the low-battery
/// banner) rather than applied everywhere.
///
/// Every field that existed before this pass keeps its name and type — nothing
/// here is a rename, only additions and value refinements — so no call site
/// elsewhere in the app needed to change.
class AppColors {
  AppColors._();

  // The robot's own body color, sampled directly from its product photo
  // (assets/robot_photo.png) and darkened just enough (same hue/saturation,
  // lower lightness) to clear WCAG AA contrast against white button text —
  // the raw sampled orange (#ED4701) only reached ~3.8:1. primaryDark/Light
  // are the same hue at further lightness steps, replacing the old
  // indigo/purple palette.
  static const primary = Color(0xFFCB3C00);
  static const primaryDark = Color(0xFF982D00);
  static const primaryLight = Color(0xFFFE6829);
  static const accent = Color(0xFF14B8A6);

  static const background = Color(0xFFF3F4F9);
  static const surface = Color(0xFFFFFFFF);
  // A second, very slightly cooler-white surface tier — used for a card
  // nested inside another card (e.g. the map preview's own frame), so
  // "layered" is a real depth cue, not just a shadow.
  static const surfaceElevated = Color(0xFFFCFCFF);
  static const surfaceSunken = Color(0xFFEEF0F6);
  static const border = Color(0xFFE5E7EF);
  static const borderStrong = Color(0xFFD7D9E4);

  // Low-alpha, primary-tinted shadow — every Card in the app casts this
  // instead of a neutral black shadow, which is most of what makes the UI
  // read as "layered" rather than "flat with borders".
  static const shadowTint = Color(0xFF982D00);

  static const textPrimary = Color(0xFF111528);
  static const textSecondary = Color(0xFF696F85);
  static const textTertiary = Color(0xFF9298AC);
  static const textOnPrimary = Color(0xFFFFFFFF);

  static const danger = Color(0xFFEF4444);
  static const warning = Color(0xFFF59E0B);
  static const success = Color(0xFF22C55E);

  // Robot state legend, matching the reference's own key exactly — reuse
  // these same names for the RobotState enum styling once that's rebuilt,
  // rather than inventing a second color mapping.
  static const stateOffline = Color(0xFF9CA3AF); // grey
  static const stateIdle = Color(0xFF22C55E); // green
  static const stateLocalizing = Color(0xFFF59E0B); // amber
  static const stateExecuting = Color(0xFF3B82F6); // blue
  static const stateTeleop = Color(0xFF8B5CF6); // purple
  static const stateDocking = Color(0xFF38BDF8); // light blue
  static const stateCharging = Color(0xFF16A34A); // bold green
  static const stateFault = Color(0xFFF97316); // orange
  static const stateEStopped = Color(0xFFEF4444); // red

  // Costmap overlay base colors — the map view's translucent color ramp
  // multiplies each cell's alpha by its cost, so these are the "fully
  // costed" endpoint, not a flat fill. Two distinct hues so global/local
  // stay visually separable when both are on at once.
  static const costmapGlobal = Color(0xFFA855F7); // purple
  static const costmapLocal = Color(0xFFF97316); // orange

  /// The robot-avatar gradient — used in exactly one place per screen (the
  /// circular avatar), so it reads as a considered accent rather than a
  /// wash applied everywhere.
  static const avatarGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryLight, primaryDark],
  );

  /// The low-battery / warning banner gradient — same restraint: one banner,
  /// one gradient.
  static const warningGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0x14EF4444), Color(0x08EF4444)],
  );
}

class AppSpacing {
  AppSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;

  static const cardRadius = 18.0;
  static const buttonRadius = 14.0;
  static const inputRadius = 12.0;
}

/// Text styles that don't fit Material's semantic TextTheme names — chiefly
/// the large tabular-figure numbers used for telemetry (battery %, speed,
/// distances). Tabular figures keep digit widths fixed so a value that ticks
/// from "9%" to "10%" doesn't visibly reflow its neighbors — a small detail
/// that reads as "instrument panel" rather than "webpage".
class AppTextStyles {
  AppTextStyles._();

  static const _tabular = [FontFeature.tabularFigures()];

  static const metricLarge = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
    height: 1.1,
    fontFeatures: _tabular,
  );

  static const metric = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.2,
    fontFeatures: _tabular,
  );

  static const metricSmall = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    fontFeatures: _tabular,
  );

  static const eyebrow = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    letterSpacing: 0.6,
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: 'Roboto',
      pageTransitionsTheme: AppMotion.pageTransitionsTheme,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineSmall: const TextStyle(
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
          letterSpacing: -0.4,
        ),
        titleLarge: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.3,
        ),
        titleMedium: const TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
          letterSpacing: -0.1,
        ),
        bodyMedium: const TextStyle(color: AppColors.textPrimary, height: 1.4),
        bodySmall:
            const TextStyle(color: AppColors.textSecondary, height: 1.35),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 3,
        // A primary-tinted shadow at very low opacity reads as depth without
        // the muddy grey a default black shadow gives a light UI — this is
        // most of what makes cards feel "layered" rather than "flat with a
        // border", and it's free: every existing `Card(...)` picks it up.
        shadowColor: AppColors.shadowTint.withValues(alpha: 0.14),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          side: const BorderSide(color: AppColors.border),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
          minimumSize: const Size.fromHeight(52),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          animationDuration: AppMotion.fast,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.border),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          ),
          animationDuration: AppMotion.fast,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          animationDuration: AppMotion.fast,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: states.contains(WidgetState.selected)
                  ? AppColors.primary
                  : AppColors.textSecondary,
            )),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        elevation: 0,
        useIndicator: true,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? AppColors.primary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary.withValues(alpha: 0.35)
              : null,
        ),
      ),
      dividerTheme:
          const DividerThemeData(color: AppColors.border, thickness: 1),
    );
  }
}
