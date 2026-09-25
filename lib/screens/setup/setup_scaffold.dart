import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/design/fade_in.dart';

/// Shared shell for every Setup: * screen — step dots with step badge,
/// top back navigation, scrollable content, and to-and-fro navigation
/// buttons (Back and Next/Primary).
/// Centered to a phone-card width on tablet/desktop rather than stretching,
/// matching the reference mockup's own proportions.
class SetupScaffold extends StatelessWidget {
  const SetupScaffold({
    super.key,
    required this.step,
    required this.totalSteps,
    required this.title,
    this.subtitle,
    required this.child,
    this.primaryLabel,
    this.onPrimary,
    this.primaryEnabled = true,
    this.primaryIcon,
    this.secondaryLabel,
    this.onSecondary,
    this.onBack,
    this.showBackButton,
    this.showBottomBackButton,
    this.backLabel,
    this.busy = false,
    this.maxWidth,
  });

  final int step;
  final int totalSteps;
  final String title;
  final String? subtitle;
  final Widget child;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final bool primaryEnabled;
  final Widget? primaryIcon;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final VoidCallback? onBack;
  final bool? showBackButton;
  final bool? showBottomBackButton;
  final String? backLabel;
  final bool busy;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final canGoBack = showBackButton ??
        (onBack != null || (step > 1 && canPop) || (step == 1 && canPop));
    final hasBottomBack = (showBottomBackButton ?? true) && canGoBack;
    final hasPrimary = primaryLabel != null;

    void handleBack() {
      if (onBack != null) {
        onBack!();
      } else if (canPop) {
        Navigator.of(context).pop();
      }
    }

    Widget? effectivePrimaryIcon;
    if (primaryIcon != null) {
      effectivePrimaryIcon = primaryIcon;
    } else if (primaryLabel != null) {
      final labelLower = primaryLabel!.toLowerCase();
      if (labelLower.contains('retry')) {
        effectivePrimaryIcon = const Icon(Icons.refresh_rounded, size: 18);
      } else if (labelLower.contains('save') ||
          labelLower.contains('connect') ||
          labelLower.contains('next') ||
          labelLower.contains('create') ||
          labelLower.contains('go to') ||
          labelLower.contains('continue')) {
        effectivePrimaryIcon =
            const Icon(Icons.arrow_forward_rounded, size: 18);
      }
    }

    return Scaffold(
      body: SafeArea(
        child: CenteredFormColumn(
          maxWidth: maxWidth ?? 440,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (canGoBack)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: Tooltip(
                          message: backLabel ?? 'Back',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: busy ? null : handleBack,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceElevated,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.border),
                              ),
                              child: const Icon(Icons.arrow_back_rounded,
                                  size: 18),
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _StepDots(step: step, totalSteps: totalSteps),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        'Step $step of $totalSteps',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                // Keyed on the title: a genuinely new step (Power -> WiFi -> ...)
                // gets a fresh FadeSlideIn entrance; rebuilds of the *same*
                // step (a field changing, a validation message appearing)
                // don't replay it.
                FadeSlideIn(
                  key: ValueKey(title),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(title,
                          style: Theme.of(context).textTheme.headlineSmall),
                      if (subtitle != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(subtitle!,
                            style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Expanded(child: child),
                const SizedBox(height: AppSpacing.md),
                if (secondaryLabel != null) ...[
                  TextButton(
                    onPressed: busy ? null : onSecondary,
                    child: Text(secondaryLabel!),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                if (hasBottomBack || hasPrimary)
                  Row(
                    children: [
                      if (hasBottomBack) ...[
                        Expanded(
                          flex: hasPrimary ? 2 : 1,
                          child: OutlinedButton.icon(
                            onPressed: busy ? null : handleBack,
                            icon:
                                const Icon(Icons.arrow_back_rounded, size: 18),
                            label: Text(backLabel ?? 'Back'),
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        if (hasPrimary) const SizedBox(width: AppSpacing.md),
                      ],
                      if (hasPrimary)
                        Expanded(
                          flex: hasBottomBack ? 3 : 1,
                          child: ElevatedButton(
                            onPressed:
                                (busy || !primaryEnabled) ? null : onPrimary,
                            style: ElevatedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: AppColors.textOnPrimary,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          primaryLabel!,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (effectivePrimaryIcon != null) ...[
                                        const SizedBox(width: AppSpacing.xs),
                                        effectivePrimaryIcon,
                                      ],
                                    ],
                                  ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.step, required this.totalSteps});

  final int step;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(totalSteps, (i) {
        final active = i < step;
        return Padding(
          padding: const EdgeInsets.only(right: AppSpacing.xs),
          child: AnimatedContainer(
            duration: AppMotion.medium,
            curve: AppMotion.settle,
            width: i == step - 1 ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: active ? AppColors.primary : AppColors.border,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }),
    );
  }
}
