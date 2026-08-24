import 'package:flutter/material.dart';

/// Raw color tokens for the redesigned (light, purple/indigo) visual system.
///
/// These are `const` values rather than `ColorScheme` lookups so that
/// non-Material consumers (map overlays, `CustomPainter`s, canvas-drawn
/// markers) can reach them without a `BuildContext`. Anything that *can* use
/// `Theme.of(context).colorScheme` / `.extension<AppStatusColors>()` should
/// prefer that instead of importing this class directly, so the palette stays
/// swappable per-theme.
class AppColors {
  AppColors._();

  /// Brand seed color driving `ColorScheme.fromSeed` for [AppTheme.lightTheme].
  /// Picked to match the BotForge reference board's purple/indigo branding;
  /// nudge this one value if the exact brand hex is provided later.
  static const Color brandSeed = Color(0xFF5B4FE9);

  // Light-theme surface/background scale (used where a raw value is needed
  // outside a ColorScheme, e.g. canvas backgrounds behind the map view).
  static const Color lightBackground = Color(0xFFF6F5FB);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFEDEBF9);
  static const Color lightOutline = Color(0xFFDFDCEF);

  // Robot-state legend — one flat set, reused by status chips, the
  // dashboard, robot status, alerts, and nav-rail badges. See
  // AppStatusColors (ThemeExtension) for the themed accessor.
  static const Color stateOffline = Color(0xFF9E9E9E); // grey
  static const Color stateIdle = Color(0xFF2FB170); // green
  static const Color stateLocalizing = Color(0xFFE8A93A); // amber
  static const Color stateExecuting = Color(0xFF3D7CF4); // blue
  static const Color stateTeleop = Color(0xFF8B5CF6); // purple
  static const Color stateDocking = Color(0xFF4FC3E8); // light blue
  static const Color stateCharging = Color(0xFF1E9E5A); // bold green
  static const Color stateFault = Color(0xFFF08A24); // orange — token only,
  // no ROS signal wired yet (see plan §7).
  static const Color stateEStopped = Color(0xFFE0453C); // red — token only,
  // no ROS signal wired yet (see plan §7).
}

/// Themed accessor for the robot-state palette in [AppColors]. Registered as
/// a `ThemeExtension` on [AppTheme.lightTheme] so widgets read
/// `Theme.of(context).extension<AppStatusColors>()!.executing` instead of
/// importing [AppColors] statically — keeps the state palette themeable and
/// swappable the same way the rest of the design system is.
@immutable
class AppStatusColors extends ThemeExtension<AppStatusColors> {
  const AppStatusColors({
    required this.offline,
    required this.idle,
    required this.localizing,
    required this.executing,
    required this.teleop,
    required this.docking,
    required this.charging,
    required this.fault,
    required this.eStopped,
  });

  final Color offline;
  final Color idle;
  final Color localizing;
  final Color executing;
  final Color teleop;
  final Color docking;
  final Color charging;
  final Color fault;
  final Color eStopped;

  static const AppStatusColors standard = AppStatusColors(
    offline: AppColors.stateOffline,
    idle: AppColors.stateIdle,
    localizing: AppColors.stateLocalizing,
    executing: AppColors.stateExecuting,
    teleop: AppColors.stateTeleop,
    docking: AppColors.stateDocking,
    charging: AppColors.stateCharging,
    fault: AppColors.stateFault,
    eStopped: AppColors.stateEStopped,
  );

  @override
  AppStatusColors copyWith({
    Color? offline,
    Color? idle,
    Color? localizing,
    Color? executing,
    Color? teleop,
    Color? docking,
    Color? charging,
    Color? fault,
    Color? eStopped,
  }) {
    return AppStatusColors(
      offline: offline ?? this.offline,
      idle: idle ?? this.idle,
      localizing: localizing ?? this.localizing,
      executing: executing ?? this.executing,
      teleop: teleop ?? this.teleop,
      docking: docking ?? this.docking,
      charging: charging ?? this.charging,
      fault: fault ?? this.fault,
      eStopped: eStopped ?? this.eStopped,
    );
  }

  @override
  AppStatusColors lerp(ThemeExtension<AppStatusColors>? other, double t) {
    if (other is! AppStatusColors) return this;
    return AppStatusColors(
      offline: Color.lerp(offline, other.offline, t)!,
      idle: Color.lerp(idle, other.idle, t)!,
      localizing: Color.lerp(localizing, other.localizing, t)!,
      executing: Color.lerp(executing, other.executing, t)!,
      teleop: Color.lerp(teleop, other.teleop, t)!,
      docking: Color.lerp(docking, other.docking, t)!,
      charging: Color.lerp(charging, other.charging, t)!,
      fault: Color.lerp(fault, other.fault, t)!,
      eStopped: Color.lerp(eStopped, other.eStopped, t)!,
    );
  }
}
