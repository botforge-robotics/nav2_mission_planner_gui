import 'package:flutter/material.dart';

import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/localize_at_dock.dart';

/// Shared across every [NotLocalizedBanner] mounted at once — Dashboard,
/// Map View, and Teleop can all show one simultaneously while the robot
/// isn't localized, and answering the "is it at the dock?" question on any
/// one of them should dismiss all three, not just the one the operator
/// happened to tap. A plain module-level ValueNotifier rather than a
/// Provider-scoped value is deliberate: these banners appear on screens
/// reached both via AppShell's own IndexedStack tabs and via Navigator.push
/// (Map View), and route-scoped Provider state already caused a real
/// "Provider not found" crash for exactly that reason this session (see
/// main.dart's MaterialApp.builder fix) — a static sidesteps that whole
/// class of bug by construction, at the cost of being real global mutable
/// state, acceptable here because there's only ever one robot connection
/// per running app instance.
final ValueNotifier<bool> dockLocalizeDismissed = ValueNotifier(false);

/// A small dismissible banner, overlaid on a live map view, that appears
/// whenever the robot isn't localized yet and asks the one question that
/// resolves the common case fast: "is it at the dock?" Confirming seeds
/// AMCL from the robot's saved dock pose (via [localizeAtDock]) — the exact
/// same action Map View's own "Robot at Dock" Localize option performs.
/// Declining calls [onDecline], which each caller wires to whatever "set
/// the pose manually" affordance makes sense for that screen (Map View
/// enters pose-picking directly; other screens open Map View to do it).
/// Either choice dismisses every instance of this banner currently mounted
/// anywhere in the app (see [dockLocalizeDismissed]).
///
/// Self-dismisses once localized-at-dock succeeds; a caller that keeps
/// showing this banner only while `!localized` will naturally stop
/// rendering it the moment a real pose arrives, so there's no separate
/// "success" state to design for here.
class NotLocalizedBanner extends StatefulWidget {
  const NotLocalizedBanner(
      {super.key, required this.api, required this.onDecline});

  final SdkApiService api;
  final VoidCallback onDecline;

  @override
  State<NotLocalizedBanner> createState() => _NotLocalizedBannerState();
}

class _NotLocalizedBannerState extends State<NotLocalizedBanner> {
  bool _busy = false;

  Future<void> _confirmAtDock() async {
    setState(() => _busy = true);
    final ok = await localizeAtDock(context: context, api: widget.api);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) dockLocalizeDismissed.value = true;
  }

  void _decline() {
    dockLocalizeDismissed.value = true;
    widget.onDecline();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: dockLocalizeDismissed,
      builder: (context, dismissed, _) {
        if (dismissed) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 6,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.location_off_rounded,
                  color: AppColors.warning, size: 16),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Text('Not localized. Is the robot at its dock?',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else ...[
                TextButton(
                  style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 10)),
                  onPressed: _decline,
                  child: const Text('No'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 12)),
                  onPressed: _confirmAtDock,
                  child: const Text('Yes'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
