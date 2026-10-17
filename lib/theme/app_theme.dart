import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_motion.dart';

/// Controller managing app-wide theme mode (light, dark, or system).
class AppThemeController extends ChangeNotifier {
  AppThemeController._();
  static final AppThemeController instance = AppThemeController._();

  static const String _prefKey = 'app_theme_mode';

  ThemeMode _mode = ThemeMode.light;
  ThemeMode get mode => _mode;

  bool get isDarkMode => _mode == ThemeMode.dark;

  /// Restores the persisted theme preference before first paint.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved == 'dark') {
        _mode = ThemeMode.dark;
      } else if (saved == 'light') {
        _mode = ThemeMode.light;
      } else if (saved == 'system') {
        _mode = ThemeMode.system;
      }
      notifyListeners();
    } catch (_) {
      // Fallback to light mode on storage errors
    }
  }

  void toggleTheme() {
    _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    _persist();
  }

  void setMode(ThemeMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    _persist();
  }

  void _persist() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_prefKey, _mode.name);
    }).catchError((_) {});
  }
}

/// Semantic ThemeExtension holding the active color palette for NavPro Mini.
/// Supports both Light Mode (clean factory floor) and Industrial Dark Mode
/// (control room HUD / nocturnal operations).
@immutable
class AppColorsTheme extends ThemeExtension<AppColorsTheme> {
  const AppColorsTheme({
    required this.primary,
    required this.primaryDark,
    required this.primaryLight,
    required this.accent,
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceSunken,
    required this.border,
    required this.borderStrong,
    required this.shadowTint,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textOnPrimary,
    required this.danger,
    required this.warning,
    required this.success,
    required this.stateOffline,
    required this.stateIdle,
    required this.stateLocalizing,
    required this.stateExecuting,
    required this.stateTeleop,
    required this.stateDocking,
    required this.stateCharging,
    required this.stateFault,
    required this.stateEStopped,
    required this.costmapGlobal,
    required this.costmapLocal,
    required this.avatarGradient,
    required this.warningGradient,
  });

  final Color primary;
  final Color primaryDark;
  final Color primaryLight;
  final Color accent;

  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceSunken;
  final Color border;
  final Color borderStrong;
  final Color shadowTint;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textOnPrimary;

  final Color danger;
  final Color warning;
  final Color success;

  final Color stateOffline;
  final Color stateIdle;
  final Color stateLocalizing;
  final Color stateExecuting;
  final Color stateTeleop;
  final Color stateDocking;
  final Color stateCharging;
  final Color stateFault;
  final Color stateEStopped;

  final Color costmapGlobal;
  final Color costmapLocal;

  final LinearGradient avatarGradient;
  final LinearGradient warningGradient;

  /// Returns true when the active theme is dark mode.
  bool get isDark => background.computeLuminance() < 0.5;

  /// Semantic informational blue tone adaptive to dark/light brightness.
  Color get info => isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);

  static AppColorsTheme of(BuildContext context) {
    final theme = Theme.of(context).extension<AppColorsTheme>();
    return theme ?? (Theme.of(context).brightness == Brightness.dark ? dark : light);
  }

  static const light = AppColorsTheme(
    primary: Color(0xFFCB3C00),
    primaryDark: Color(0xFF982D00),
    primaryLight: Color(0xFFFE6829),
    accent: Color(0xFF14B8A6),
    background: Color(0xFFF3F4F9),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFCFCFF),
    surfaceSunken: Color(0xFFEEF0F6),
    border: Color(0xFFE5E7EF),
    borderStrong: Color(0xFFD7D9E4),
    shadowTint: Color(0xFF982D00),
    textPrimary: Color(0xFF111528),
    textSecondary: Color(0xFF696F85),
    textTertiary: Color(0xFF9298AC),
    textOnPrimary: Color(0xFFFFFFFF),
    danger: Color(0xFFEF4444),
    warning: Color(0xFFF59E0B),
    success: Color(0xFF22C55E),
    stateOffline: Color(0xFF9CA3AF),
    stateIdle: Color(0xFF22C55E),
    stateLocalizing: Color(0xFFF59E0B),
    stateExecuting: Color(0xFF3B82F6),
    stateTeleop: Color(0xFF8B5CF6),
    stateDocking: Color(0xFF38BDF8),
    stateCharging: Color(0xFF16A34A),
    stateFault: Color(0xFFF97316),
    stateEStopped: Color(0xFFEF4444),
    costmapGlobal: Color(0xFFA855F7),
    costmapLocal: Color(0xFFF97316),
    avatarGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFE6829), Color(0xFF982D00)],
    ),
    warningGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0x14EF4444), Color(0x08EF4444)],
    ),
  );

  static const dark = AppColorsTheme(
    primary: Color(0xFFFF5500),
    primaryDark: Color(0xFFCC4400),
    primaryLight: Color(0xFFFF7733),
    accent: Color(0xFF2DD4BF),
    background: Color(0xFF0B0E14),
    surface: Color(0xFF121721),
    surfaceElevated: Color(0xFF1A2230),
    surfaceSunken: Color(0xFF080A0F),
    border: Color(0xFF232B3B),
    borderStrong: Color(0xFF333F54),
    shadowTint: Color(0xFF000000),
    textPrimary: Color(0xFFE6EDF3),
    textSecondary: Color(0xFF94A3B8),
    textTertiary: Color(0xFF64748B),
    textOnPrimary: Color(0xFFFFFFFF),
    danger: Color(0xFFF87171),
    warning: Color(0xFFFBBF24),
    success: Color(0xFF34D399),
    stateOffline: Color(0xFF64748B),
    stateIdle: Color(0xFF34D399),
    stateLocalizing: Color(0xFFFBBF24),
    stateExecuting: Color(0xFF60A5FA),
    stateTeleop: Color(0xFFA78BFA),
    stateDocking: Color(0xFF38BDF8),
    stateCharging: Color(0xFF22C55E),
    stateFault: Color(0xFFFB923C),
    stateEStopped: Color(0xFFF87171),
    costmapGlobal: Color(0xFFC084FC),
    costmapLocal: Color(0xFFFB923C),
    avatarGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFF7733), Color(0xFFCC4400)],
    ),
    warningGradient: LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [Color(0x28EF4444), Color(0x14EF4444)],
    ),
  );

  @override
  AppColorsTheme copyWith({
    Color? primary,
    Color? primaryDark,
    Color? primaryLight,
    Color? accent,
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceSunken,
    Color? border,
    Color? borderStrong,
    Color? shadowTint,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textOnPrimary,
    Color? danger,
    Color? warning,
    Color? success,
    Color? stateOffline,
    Color? stateIdle,
    Color? stateLocalizing,
    Color? stateExecuting,
    Color? stateTeleop,
    Color? stateDocking,
    Color? stateCharging,
    Color? stateFault,
    Color? stateEStopped,
    Color? costmapGlobal,
    Color? costmapLocal,
    LinearGradient? avatarGradient,
    LinearGradient? warningGradient,
  }) {
    return AppColorsTheme(
      primary: primary ?? this.primary,
      primaryDark: primaryDark ?? this.primaryDark,
      primaryLight: primaryLight ?? this.primaryLight,
      accent: accent ?? this.accent,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      shadowTint: shadowTint ?? this.shadowTint,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textOnPrimary: textOnPrimary ?? this.textOnPrimary,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      success: success ?? this.success,
      stateOffline: stateOffline ?? this.stateOffline,
      stateIdle: stateIdle ?? this.stateIdle,
      stateLocalizing: stateLocalizing ?? this.stateLocalizing,
      stateExecuting: stateExecuting ?? this.stateExecuting,
      stateTeleop: stateTeleop ?? this.stateTeleop,
      stateDocking: stateDocking ?? this.stateDocking,
      stateCharging: stateCharging ?? this.stateCharging,
      stateFault: stateFault ?? this.stateFault,
      stateEStopped: stateEStopped ?? this.stateEStopped,
      costmapGlobal: costmapGlobal ?? this.costmapGlobal,
      costmapLocal: costmapLocal ?? this.costmapLocal,
      avatarGradient: avatarGradient ?? this.avatarGradient,
      warningGradient: warningGradient ?? this.warningGradient,
    );
  }

  @override
  AppColorsTheme lerp(ThemeExtension<AppColorsTheme>? other, double t) {
    if (other is! AppColorsTheme) return this;
    return AppColorsTheme(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      shadowTint: Color.lerp(shadowTint, other.shadowTint, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textOnPrimary: Color.lerp(textOnPrimary, other.textOnPrimary, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      success: Color.lerp(success, other.success, t)!,
      stateOffline: Color.lerp(stateOffline, other.stateOffline, t)!,
      stateIdle: Color.lerp(stateIdle, other.stateIdle, t)!,
      stateLocalizing: Color.lerp(stateLocalizing, other.stateLocalizing, t)!,
      stateExecuting: Color.lerp(stateExecuting, other.stateExecuting, t)!,
      stateTeleop: Color.lerp(stateTeleop, other.stateTeleop, t)!,
      stateDocking: Color.lerp(stateDocking, other.stateDocking, t)!,
      stateCharging: Color.lerp(stateCharging, other.stateCharging, t)!,
      stateFault: Color.lerp(stateFault, other.stateFault, t)!,
      stateEStopped: Color.lerp(stateEStopped, other.stateEStopped, t)!,
      costmapGlobal: Color.lerp(costmapGlobal, other.costmapGlobal, t)!,
      costmapLocal: Color.lerp(costmapLocal, other.costmapLocal, t)!,
      avatarGradient: LinearGradient.lerp(avatarGradient, other.avatarGradient, t)!,
      warningGradient: LinearGradient.lerp(warningGradient, other.warningGradient, t)!,
    );
  }
}

/// Static color constants retained for 100% backward compatibility across call sites.
/// New widgets can also call `AppColors.of(context)` to resolve the active theme palette.
abstract final class AppColors {
  static AppColorsTheme of(BuildContext context) => AppColorsTheme.of(context);

  static const primary = Color(0xFFCB3C00);
  static const primaryDark = Color(0xFF982D00);
  static const primaryLight = Color(0xFFFE6829);
  static const accent = Color(0xFF14B8A6);

  static const background = Color(0xFFF3F4F9);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceElevated = Color(0xFFFCFCFF);
  static const surfaceSunken = Color(0xFFEEF0F6);
  static const border = Color(0xFFE5E7EF);
  static const borderStrong = Color(0xFFD7D9E4);
  static const shadowTint = Color(0xFF982D00);

  static const textPrimary = Color(0xFF111528);
  static const textSecondary = Color(0xFF696F85);
  static const textTertiary = Color(0xFF9298AC);
  static const textOnPrimary = Color(0xFFFFFFFF);

  static const danger = Color(0xFFEF4444);
  static const warning = Color(0xFFF59E0B);
  static const success = Color(0xFF22C55E);

  static const stateOffline = Color(0xFF9CA3AF);
  static const stateIdle = Color(0xFF22C55E);
  static const stateLocalizing = Color(0xFFF59E0B);
  static const stateExecuting = Color(0xFF3B82F6);
  static const stateTeleop = Color(0xFF8B5CF6);
  static const stateDocking = Color(0xFF38BDF8);
  static const stateCharging = Color(0xFF16A34A);
  static const stateFault = Color(0xFFF97316);
  static const stateEStopped = Color(0xFFEF4444);

  static const costmapGlobal = Color(0xFFA855F7);
  static const costmapLocal = Color(0xFFF97316);

  static const avatarGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryLight, primaryDark],
  );

  static const warningGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0x14EF4444), Color(0x08EF4444)],
  );
}

abstract final class AppSpacing {
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

/// Text styles with tabular figures for jitter-free telemetry readouts.
abstract final class AppTextStyles {
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

abstract final class AppTheme {
  /// Factory Floor Light Theme (Clean, Crisp, Daytime High Visibility).
  static ThemeData get light {
    const c = AppColorsTheme.light;
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: c.primary,
        primary: c.primary,
        surface: c.surface,
      ),
      scaffoldBackgroundColor: c.background,
      fontFamily: 'Roboto',
      pageTransitionsTheme: AppMotion.pageTransitionsTheme,
      splashFactory: InkSparkle.splashFactory,
      extensions: const [c],
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineSmall: TextStyle(
          fontWeight: FontWeight.w800,
          color: c.textPrimary,
          letterSpacing: -0.4,
        ),
        titleLarge: TextStyle(
          fontWeight: FontWeight.w700,
          color: c.textPrimary,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
          letterSpacing: -0.1,
        ),
        bodyMedium: TextStyle(color: c.textPrimary, height: 1.4),
        bodySmall: TextStyle(color: c.textSecondary, height: 1.35),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        toolbarHeight: 46,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: c.textPrimary,
          letterSpacing: -0.4,
          fontFamily: 'Roboto',
        ),
        shape: Border(
          bottom: BorderSide(
            color: c.border,
            width: 1.0,
          ),
        ),
        iconTheme: IconThemeData(
          color: c.textPrimary,
          size: 20,
        ),
        actionsIconTheme: IconThemeData(
          color: c.textPrimary,
          size: 20,
        ),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 3,
        shadowColor: c.shadowTint.withValues(alpha: 0.14),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          side: BorderSide(color: c.border),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.textOnPrimary,
          disabledBackgroundColor: c.primary.withValues(alpha: 0.4),
          minimumSize: const Size(64, 48),
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
          foregroundColor: c.primary,
          side: BorderSide(color: c.border),
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          ),
          animationDuration: AppMotion.fast,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          animationDuration: AppMotion.fast,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
          borderSide: BorderSide(color: c.primary, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.primary.withValues(alpha: 0.12),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: states.contains(WidgetState.selected)
                  ? c.primary
                  : c.textSecondary,
            )),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.primary.withValues(alpha: 0.12),
        elevation: 0,
        useIndicator: true,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? c.primary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.primary.withValues(alpha: 0.35)
              : null,
        ),
      ),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1),
    );
  }

  /// Industrial Cockpit Dark Theme (Low Glare, Nocturnal & Control-Room HUD).
  static ThemeData get dark {
    const c = AppColorsTheme.dark;
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: c.primary,
        onPrimary: c.textOnPrimary,
        secondary: c.accent,
        onSecondary: const Color(0xFF000000),
        surface: c.surface,
        onSurface: c.textPrimary,
        error: c.danger,
        onError: const Color(0xFF000000),
      ),
      scaffoldBackgroundColor: c.background,
      fontFamily: 'Roboto',
      pageTransitionsTheme: AppMotion.pageTransitionsTheme,
      splashFactory: InkSparkle.splashFactory,
      extensions: const [c],
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineSmall: TextStyle(
          fontWeight: FontWeight.w800,
          color: c.textPrimary,
          letterSpacing: -0.4,
        ),
        titleLarge: TextStyle(
          fontWeight: FontWeight.w700,
          color: c.textPrimary,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          fontWeight: FontWeight.w600,
          color: c.textPrimary,
          letterSpacing: -0.1,
        ),
        bodyMedium: TextStyle(color: c.textPrimary, height: 1.4),
        bodySmall: TextStyle(color: c.textSecondary, height: 1.35),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        toolbarHeight: 46,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: c.textPrimary,
          letterSpacing: -0.4,
          fontFamily: 'Roboto',
        ),
        shape: Border(
          bottom: BorderSide(
            color: c.border,
            width: 1.0,
          ),
        ),
        iconTheme: IconThemeData(
          color: c.textPrimary,
          size: 20,
        ),
        actionsIconTheme: IconThemeData(
          color: c.textPrimary,
          size: 20,
        ),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 1,
        shadowColor: c.shadowTint.withValues(alpha: 0.40),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          side: BorderSide(color: c.border),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.textOnPrimary,
          disabledBackgroundColor: c.primary.withValues(alpha: 0.4),
          minimumSize: const Size(64, 48),
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
          foregroundColor: c.primary,
          side: BorderSide(color: c.border),
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          ),
          animationDuration: AppMotion.fast,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          animationDuration: AppMotion.fast,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceSunken,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
          borderSide: BorderSide(color: c.primary, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.primary.withValues(alpha: 0.20),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: states.contains(WidgetState.selected)
                  ? c.primary
                  : c.textSecondary,
            )),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.primary.withValues(alpha: 0.20),
        elevation: 0,
        useIndicator: true,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? c.primary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.primary.withValues(alpha: 0.35)
              : null,
        ),
      ),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1),
    );
  }
}
