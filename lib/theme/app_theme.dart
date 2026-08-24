import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

class AppTheme {
  // --- Legacy dark-theme tokens -------------------------------------------
  // Kept as-is (not renamed/removed) so the not-yet-restyled screens that
  // still reference these directly (toolbarColor, secondaryColor,
  // backgroundColor, statusBarHeight) keep working unchanged during the
  // phased migration to AppTheme.lightTheme. New screens should prefer
  // Theme.of(context)/AppColors/AppSpacing/AppTypography instead of adding
  // new call sites here.
  static const primaryColor = Color(0xFF121212); // Very dark gray
  static const secondaryColor = Color(0xFF2A2A2A); // Dark gray
  static const accentColor = Color(0xFF404040); // Medium gray
  static const backgroundColor = Color(0xFF0A0A0A); // Almost black gray
  static const toolbarColor =
      Color.fromARGB(255, 22, 22, 22); // Dark blue-gray color

  static const double toolbarWidth = 60.0;
  static const double statusBarHeight = 50.0;
  static const double controlPanelWidth = 300.0;

  static const TextStyle statusTextStyle = TextStyle(
    color: Colors.white,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle titleTextStyle = TextStyle(
    color: Colors.white,
    fontSize: 16,
    fontWeight: FontWeight.bold,
  );

  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: backgroundColor,
      canvasColor: backgroundColor,
      primaryColor: primaryColor,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: secondaryColor,
        surface: backgroundColor,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: toolbarColor,
        elevation: 0,
      ),
    );
  }

  // --- Redesigned light theme ----------------------------------------------
  // Material 3, purple/indigo brand seed, built from the token files in
  // this folder (app_colors.dart / app_typography.dart / app_spacing.dart).
  // Screens are migrated onto this incrementally; `main.dart` only flips
  // `theme:`/`themeMode:` over to it once enough screens are restyled, so
  // there's a rollback path throughout.
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.brandSeed,
      brightness: Brightness.light,
    );

    final baseTextTheme = Typography.material2021(
      colorScheme: colorScheme,
    ).black;
    final textTheme = baseTextTheme.merge(AppTypography.textTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.lightBackground,
      canvasColor: AppColors.lightBackground,
      textTheme: textTheme,
      extensions: const [AppStatusColors.standard],
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.lightSurface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: AppColors.lightSurface,
        elevation: AppSpacing.elevationCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: const BorderSide(color: AppColors.lightOutline),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.lightSurfaceVariant,
        labelStyle: textTheme.labelMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide.none,
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.lightSurface,
        selectedIconTheme: IconThemeData(color: colorScheme.primary),
        selectedLabelTextStyle:
            textTheme.labelMedium?.copyWith(color: colorScheme.primary),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        unselectedLabelTextStyle: textTheme.labelMedium,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.lightOutline),
    );
  }
}
