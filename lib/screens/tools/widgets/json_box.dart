import 'package:flutter/material.dart';
import '../../../theme/app_spacing.dart';

/// Small "200 OK"-style status chip shown next to a service/action
/// response — echoes the reference design's Call API response badge.
/// `ok == null` renders nothing (no call made yet).
class ResultStatusChip extends StatelessWidget {
  final bool? ok;

  const ResultStatusChip({super.key, required this.ok});

  @override
  Widget build(BuildContext context) {
    if (ok == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final color = ok! ? const Color(0xFF2FB170) : theme.colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        ok! ? 'OK' : 'Failed',
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

/// Scrollable monospace read-out box shared by all three Tools panels
/// (topic messages, service responses, action results/feedback).
class JsonBox extends StatelessWidget {
  final String text;
  final double maxHeight;

  const JsonBox({super.key, required this.text, this.maxHeight = 240});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: 80, maxHeight: maxHeight),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }
}
