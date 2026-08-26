import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/design/fade_in.dart';

/// Shared shell for every Setup: * screen — step dots, title/subtitle,
/// scrollable content, and a bottom primary action. Centered to a
/// phone-card width on tablet/desktop rather than stretching, matching the
/// reference mockup's own proportions.
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
    this.secondaryLabel,
    this.onSecondary,
    this.busy = false,
  });

  final int step;
  final int totalSteps;
  final String title;
  final String? subtitle;
  final Widget child;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final bool primaryEnabled;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CenteredFormColumn(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StepDots(step: step, totalSteps: totalSteps),
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
                if (secondaryLabel != null)
                  TextButton(
                    onPressed: busy ? null : onSecondary,
                    child: Text(secondaryLabel!),
                  ),
                if (primaryLabel != null)
                  ElevatedButton(
                    onPressed: (busy || !primaryEnabled) ? null : onPrimary,
                    child: busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: AppColors.textOnPrimary,
                            ),
                          )
                        : Text(primaryLabel!),
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
