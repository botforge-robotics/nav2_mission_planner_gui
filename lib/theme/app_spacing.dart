/// Spacing / corner-radius / elevation scale for the redesigned visual
/// system. Replaces hardcoded `EdgeInsets`/`BorderRadius.circular(n)`
/// literals scattered per-widget with a shared, named scale.
///
/// Legacy fixed-pixel layout constants (`AppTheme.toolbarWidth`,
/// `statusBarHeight`, `controlPanelWidth`) intentionally stay on `AppTheme`
/// rather than moving here — several not-yet-restyled widgets size off them
/// today and this file is additive, new-screens-only, during the migration.
class AppSpacing {
  AppSpacing._();

  // Spacing scale
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  // Corner-radius scale
  static const double radiusSm = 4;
  static const double radiusMd = 8;
  static const double radiusLg = 12;
  static const double radiusXl = 16;

  // Elevation scale (Material 3 surface tint applies automatically; these
  // are the `elevation:` values passed to card/sheet/dialog themes).
  static const double elevationCard = 0;
  static const double elevationRaised = 1;
  static const double elevationSheet = 3;
  static const double elevationDialog = 6;
}
