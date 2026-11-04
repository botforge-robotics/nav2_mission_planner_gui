import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/connection_provider.dart';
import '../../services/motion_settings_controller.dart';
import '../../services/sdk_api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/design/fade_in.dart';

/// Screen for tuning robot autonomous motion, acceleration, and docking parameters.
///
/// Single Source of Truth:
/// The robot's SQLite database (~/.navpromini_sdk.db) holds the authoritative copy.
/// The GUI holds no local truth; it fetches from the robot on mount and saves back to it.
class MotionSettingsScreen extends StatefulWidget {
  final String? robotIp;
  const MotionSettingsScreen({super.key, this.robotIp});

  @override
  State<MotionSettingsScreen> createState() => _MotionSettingsScreenState();
}

class _MotionSettingsScreenState extends State<MotionSettingsScreen> {
  late SdkApiService _api;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final conn = context.read<ConnectionProvider>();
      final ip = widget.robotIp ?? conn.robot?.ip ?? '192.168.0.128';
      _api = SdkApiService(ip);
      MotionSettingsController.instance.refresh(_api);
    }
  }

  Future<void> _handleSave() async {
    HapticFeedback.mediumImpact();
    final ok = await MotionSettingsController.instance.save(_api);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    if (ok) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Speed settings saved successfully.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      final err = MotionSettingsController.instance.value.error ?? 'Save failed';
      messenger.showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleRestoreDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore Default Speeds?'),
        content: const Text(
          'Reset all speed settings back to default values?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore Defaults'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    HapticFeedback.heavyImpact();
    final ok = await MotionSettingsController.instance.restoreDefaults(_api);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    if (ok) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Default speeds restored.'),
          backgroundColor: Colors.blueAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      final err = MotionSettingsController.instance.value.error ?? 'Restore failed';
      messenger.showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleSetCurrentAsDefault() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Present as Default?'),
        content: const Text(
          'Save the current speed settings as the new default speeds?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Set as Default'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    HapticFeedback.mediumImpact();
    final ok = await MotionSettingsController.instance.setCurrentAsDefault(_api);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    if (ok) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Present speeds saved as new default speeds.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      final err = MotionSettingsController.instance.value.error ?? 'Failed to set default';
      messenger.showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Speed Settings'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              HapticFeedback.lightImpact();
              MotionSettingsController.instance.refresh(_api);
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'More Options',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (val) {
              if (val == 'set_default') {
                _handleSetCurrentAsDefault();
              } else if (val == 'restore') {
                _handleRestoreDefaults();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'set_default',
                child: Row(
                  children: [
                    Icon(Icons.bookmark_add_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('Set Present as Default'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'restore',
                child: Row(
                  children: [
                    Icon(Icons.restore_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('Restore Defaults'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ValueListenableBuilder<MotionSettingsState>(
          valueListenable: MotionSettingsController.instance,
          builder: (context, state, _) {
            if (state.isLoading && state.settings.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading speed settings...'),
                  ],
                ),
              );
            }

            return CenteredFormColumn(
              maxWidth: Breakpoints.of(context) == DeviceClass.desktop ? 840 : 640,
              child: FadeSlideIn(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  children: [
                    if (state.error != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: AppSpacing.md),
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                state.error!,
                                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Section 1: Cruising Speed
                    _buildSectionCard(
                      context,
                      title: 'Speed & Cruising',
                      icon: Icons.speed_rounded,
                      color: Colors.blueAccent,
                      children: [
                        _buildParamSlider(
                          context,
                          paramKey: 'max_linear_speed',
                          state: state,
                          labelOverride: 'Maximum Speed',
                          hint: 'Top autonomous cruising speed in open pathways',
                        ),
                        const Divider(height: 24),
                        _buildParamSlider(
                          context,
                          paramKey: 'min_linear_speed',
                          state: state,
                          labelOverride: 'Minimum Approach Speed',
                          hint: 'Creep speed when arriving at target locations',
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Section 2: Turning Speed
                    _buildSectionCard(
                      context,
                      title: 'Turning Speed',
                      icon: Icons.rotate_right_rounded,
                      color: Colors.purpleAccent,
                      children: [
                        _buildParamSlider(
                          context,
                          paramKey: 'max_angular_speed',
                          state: state,
                          labelOverride: 'Turn Speed',
                          hint: 'Rotation speed during navigation turns',
                          unitTransform: (v) => '${v.toStringAsFixed(2)} rad/s (~${(v * 180 / pi).toStringAsFixed(1)}°/s)',
                        ),
                        const Divider(height: 24),
                        _buildParamSlider(
                          context,
                          paramKey: 'min_angular_speed',
                          state: state,
                          labelOverride: 'Minimum Turn Speed',
                          hint: 'Minimum rotation speed threshold',
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Section 3: Acceleration & Deceleration
                    _buildSectionCard(
                      context,
                      title: 'Acceleration & Deceleration',
                      icon: Icons.bolt_rounded,
                      color: Colors.amber,
                      children: [
                        _buildParamSlider(
                          context,
                          paramKey: 'linear_accel',
                          state: state,
                          labelOverride: 'Linear Accel & Decel',
                          hint: 'Single slider controlling both linear acceleration and braking deceleration rate',
                          unitTransform: (v) {
                            final dec = (state.settings['linear_decel'] ?? -v * 1.33).abs();
                            return '+${v.toStringAsFixed(2)} / -${dec.toStringAsFixed(2)} m/s²';
                          },
                        ),
                        const Divider(height: 24),
                        _buildParamSlider(
                          context,
                          paramKey: 'angular_accel',
                          state: state,
                          labelOverride: 'Turn Accel & Decel',
                          hint: 'Single slider controlling rotational acceleration entering and exiting turns',
                          unitTransform: (v) => '${v.toStringAsFixed(2)} rad/s² (~${(v * 180 / pi).toStringAsFixed(0)}°/s²)',
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Section 4: Docking & Undocking
                    _buildSectionCard(
                      context,
                      title: 'Docking & Undocking',
                      icon: Icons.ev_station_rounded,
                      color: Colors.tealAccent,
                      children: [
                        _buildParamSlider(
                          context,
                          paramKey: 'undock_speed',
                          state: state,
                          labelOverride: 'Undock Speed',
                          hint: 'Speed when leaving the charging station',
                        ),
                        const Divider(height: 24),
                        _buildParamSlider(
                          context,
                          paramKey: 'dock_speed',
                          state: state,
                          labelOverride: 'Dock Approach Speed',
                          hint: 'Approach speed when docking (automatically slows down near contacts)',
                        ),
                      ],
                    ),
                    const SizedBox(height: 100), // Spacing for floating bottom bar
                  ],
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: ValueListenableBuilder<MotionSettingsState>(
        valueListenable: MotionSettingsController.instance,
        builder: (context, state, _) {
          return _buildBottomBar(context, state);
        },
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildParamSlider(
    BuildContext context, {
    required String paramKey,
    required MotionSettingsState state,
    String? labelOverride,
    String? hint,
    String Function(double)? unitTransform,
  }) {
    final limits = state.safetyLimits[paramKey] as Map<String, dynamic>?;
    final minVal = (limits?['min'] as num?)?.toDouble() ?? 0.0;
    final maxVal = (limits?['max'] as num?)?.toDouble() ?? 1.0;
    final step = (limits?['step'] as num?)?.toDouble() ?? 0.01;
    final unit = (limits?['unit'] as String?) ?? '';
    final label = labelOverride ?? (limits?['label'] as String?) ?? paramKey;
    final desc = hint ?? (limits?['desc'] as String?);

    final currentVal = state.settings[paramKey] ?? minVal;
    final defaultVal = state.defaults[paramKey];

    final isDefault = defaultVal != null && (currentVal - defaultVal).abs() < 1e-4;
    final formattedValue = unitTransform != null
        ? unitTransform(currentVal)
        : '${currentVal.toStringAsFixed(2)} $unit';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
              ),
              child: Text(
                formattedValue,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.blueAccent,
                ),
              ),
            ),
          ],
        ),
        if (desc != null && desc.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            desc,
            style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline_rounded, size: 22),
              visualDensity: VisualDensity.compact,
              onPressed: currentVal > minVal
                  ? () {
                      HapticFeedback.selectionClick();
                      final next = max(minVal, currentVal - step);
                      MotionSettingsController.instance.updateParam(
                        paramKey,
                        double.parse(next.toStringAsFixed(2)),
                      );
                    }
                  : null,
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                ),
                child: Slider(
                  value: currentVal.clamp(minVal, maxVal),
                  min: minVal,
                  max: maxVal,
                  divisions: ((maxVal - minVal) / step).round(),
                  onChanged: (val) {
                    MotionSettingsController.instance.updateParam(
                      paramKey,
                      double.parse(val.toStringAsFixed(2)),
                    );
                  },
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
              visualDensity: VisualDensity.compact,
              onPressed: currentVal < maxVal
                  ? () {
                      HapticFeedback.selectionClick();
                      final next = min(maxVal, currentVal + step);
                      MotionSettingsController.instance.updateParam(
                        paramKey,
                        double.parse(next.toStringAsFixed(2)),
                      );
                    }
                  : null,
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Range: ${minVal.toStringAsFixed(2)} – ${maxVal.toStringAsFixed(2)} $unit',
              style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline),
            ),
            if (defaultVal != null)
              InkWell(
                onTap: isDefault
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        MotionSettingsController.instance.updateParam(paramKey, defaultVal);
                      },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    children: [
                      Icon(
                        isDefault ? Icons.check_circle_rounded : Icons.restore_rounded,
                        size: 11,
                        color: isDefault ? Colors.green : Colors.blueAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Default: ${defaultVal.toStringAsFixed(2)} $unit',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isDefault ? FontWeight.normal : FontWeight.w600,
                          color: isDefault ? Colors.green : Colors.blueAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context, MotionSettingsState state) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161A20) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.restore_rounded, size: 18),
            label: const Text('Defaults'),
            onPressed: state.isSaving ? null : _handleRestoreDefaults,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: FilledButton.icon(
              icon: state.isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: Text(
                state.isSaving
                    ? 'Saving...'
                    : state.isDirty
                        ? 'Save Settings'
                        : 'Settings Saved',
              ),
              onPressed: state.isSaving || !state.isDirty ? null : _handleSave,
            ),
          ),
        ],
      ),
    );
  }
}
