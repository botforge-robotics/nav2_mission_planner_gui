import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';

/// A single honest stand-in for every reference settings panel that has no
/// real backend to build against yet (Users & Roles, Robot Behavior, Map
/// Settings, Notification Settings) — explains *why*, rather than shipping
/// toggles that silently do nothing.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen(
      {super.key, required this.title, required this.explanation});

  final String title;
  final String explanation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: CenteredFormColumn(
          maxWidth: 480,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.construction_rounded,
                    size: 40, color: AppColors.textSecondary),
                const SizedBox(height: AppSpacing.md),
                Text('Not available yet',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  explanation,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
