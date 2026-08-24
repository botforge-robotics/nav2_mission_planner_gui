import 'package:flutter/material.dart';
import '../../../theme/app_spacing.dart';

class VelocityControl extends StatelessWidget {
  final double value;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final ValueChanged<double?> onChanged;
  final Size screenSize;
  final Color modeColor;

  const VelocityControl({
    super.key,
    required this.value,
    required this.onIncrement,
    required this.onDecrement,
    required this.onChanged,
    required this.screenSize,
    required this.modeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _StepButton(icon: Icons.remove, color: modeColor, onTap: onDecrement),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 84,
          child: TextFormField(
            textAlign: TextAlign.center,
            controller: TextEditingController(
              text: value.toStringAsFixed(2),
            ),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                vertical: AppSpacing.md,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                borderSide: BorderSide(color: modeColor),
              ),
            ),
            onChanged: (value) {
              final parsed = double.tryParse(value);
              if (parsed != null) onChanged(parsed);
            },
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _StepButton(icon: Icons.add, color: modeColor, onTap: onIncrement),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _StepButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}
