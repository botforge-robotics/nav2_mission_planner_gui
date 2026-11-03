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
          content: Text('Motion parameters saved to robot database & active nodes.'),
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
        title: const Text('Restore Default Motion Parameters?'),
        content: const Text(
          'This will reset all speeds and auto-computed dynamics '
          'to their finalized baseline defaults in the robot database:\n\n'
          '• Max Speed: 0.35 m/s\n'
          '• Linear Accel: Auto (0.35 / 4 = 0.088 m/s²)\n'
          '• Linear Decel: Auto (-0.35 / 2 = -0.175 m/s²)\n'
          '• Angular Speed: 0.30 rad/s (~17°/s)\n'
          '• Angular Accel: Auto (0.30 × 1.67 = 0.50 rad/s²)\n'
          '• Undock Speed: 0.13 m/s (doubled)\n'
          '• Dock Approach: 0.13 m/s (staged taper)',
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
          content: Text('Calibrated defaults restored in robot database.'),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Motion & Speed Tuning'),
        actions: [
          IconButton(
            tooltip: 'Re-fetch from Robot',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              HapticFeedback.lightImpact();
              MotionSettingsController.instance.refresh(_api);
            },
          ),
          IconButton(
            tooltip: 'Restore Defaults',
            icon: const Icon(Icons.restore_rounded),
            onPressed: _handleRestoreDefaults,
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
                    Text('Reading dynamic parameters from robot database...'),
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
                    _buildHeaderBanner(context, state, isDark),
                    const SizedBox(height: AppSpacing.md),

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

                    // Section 1: Linear Speed & Cruising
                    _buildSectionCard(
                      context,
                      title: 'Linear Speed & Cruising',
                      icon: Icons.speed_rounded,
                      color: Colors.blueAccent,
                      children: [
                        _buildParamSlider(
                          context,
                          paramKey: 'max_linear_speed',
                          state: state,
                        ),
                        const Divider(height: 24),
                        _buildParamSlider(
                          context,
                          paramKey: 'min_linear_speed',
                          state: state,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Section 2: Formula-Derived Acceleration & Deceleration (Auto-Configured)
                    _buildAutoDynamicsCard(context, state),
                    const SizedBox(height: AppSpacing.md),

                    // Section 3: Angular Velocity & Heading Turns
                    _buildSectionCard(
                      context,
                      title: 'Angular Dynamics & Turns',
                      icon: Icons.rotate_right_rounded,
                      color: Colors.purpleAccent,
                      children: [
                        _buildParamSlider(
                          context,
                          paramKey: 'max_angular_speed',
                          state: state,
                          unitTransform: (v) => '${v.toStringAsFixed(2)} rad/s (~${(v * 180 / pi).toStringAsFixed(1)}°/s)',
                        ),
                        const Divider(height: 24),
                        _buildParamSlider(
                          context,
                          paramKey: 'min_angular_speed',
                          state: state,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Section 4: Docking & Undocking Velocities
                    _buildSectionCard(
                      context,
                      title: 'Docking & Undocking Dynamics',
                      icon: Icons.ev_station_rounded,
                      color: Colors.tealAccent,
                      children: [
                        _buildParamSlider(
                          context,
                          paramKey: 'undock_speed',
                          state: state,
                          hint: 'Doubled speed (0.13 m/s) swiftly drives clear of the charging slot.',
                        ),
                        const Divider(height: 24),
                        _buildParamSlider(
                          context,
                          paramKey: 'dock_speed',
                          state: state,
                          hint: 'Doubled speed when far (>60cm), automatically tapering down to 0.022 m/s near contacts.',
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

  Widget _buildHeaderBanner(BuildContext context, MotionSettingsState state, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E232A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.storage_rounded, color: Colors.blueAccent, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Robot SQLite Database',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Colors.greenAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'SYNCED',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Dynamic source of truth on ~/.navpromini_sdk.db. Safety clamped.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
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

  Widget _buildAutoDynamicsCard(BuildContext context, MotionSettingsState state) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final maxLin = state.settings['max_linear_speed'] ?? 0.35;
    final maxAng = state.settings['max_angular_speed'] ?? 0.30;

    final accel = state.settings['linear_accel'] ?? (maxLin / 4.0);
    final decel = state.settings['linear_decel'] ?? (-maxLin / 2.0);
    final angAccel = state.settings['angular_accel'] ?? (maxAng * 1.67);

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
                const Icon(Icons.auto_awesome_rounded, size: 20, color: Colors.amberAccent),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Auto-Configured Acceleration & Deceleration',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.functions_rounded, size: 12, color: Colors.amber),
                      SizedBox(width: 4),
                      Text(
                        'FORMULA-SYNCED',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Acceleration and deceleration are automatically derived from maximum speeds '
              'to eliminate manual guesswork, prevent tile wheel slip, and enforce safe stopping distance.',
              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            _buildFormulaRow(
              context,
              title: 'Linear Acceleration',
              formula: 'a = v_max / 4',
              valueText: '+${accel.toStringAsFixed(3)} m/s²',
              description: 'Ramps smoothly from 0 to max speed in ~4.0s without wheel slip or odometry drift.',
              accentColor: Colors.amber,
            ),
            const SizedBox(height: 10),
            _buildFormulaRow(
              context,
              title: 'Linear Deceleration',
              formula: 'd = -v_max / 2',
              valueText: '${decel.toStringAsFixed(3)} m/s²',
              description: 'Progressive braking deceleration stopping safely in ~2.0s without forward pitch or skid.',
              accentColor: Colors.deepOrangeAccent,
            ),
            const SizedBox(height: 10),
            _buildFormulaRow(
              context,
              title: 'Angular Acceleration',
              formula: 'α = ω_max × 1.67',
              valueText: '${angAccel.toStringAsFixed(2)} rad/s²',
              description: 'Soft progressive rotational acceleration rate entering and exiting heading turns.',
              accentColor: Colors.purpleAccent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormulaRow(
    BuildContext context, {
    required String title,
    required String formula,
    required String valueText,
    required String description,
    required Color accentColor,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        formula,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  valueText,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParamSlider(
    BuildContext context, {
    required String paramKey,
    required MotionSettingsState state,
    String? hint,
    String Function(double)? unitTransform,
  }) {
    final limits = state.safetyLimits[paramKey] as Map<String, dynamic>?;
    final minVal = (limits?['min'] as num?)?.toDouble() ?? 0.0;
    final maxVal = (limits?['max'] as num?)?.toDouble() ?? 1.0;
    final step = (limits?['step'] as num?)?.toDouble() ?? 0.01;
    final unit = (limits?['unit'] as String?) ?? '';
    final label = (limits?['label'] as String?) ?? paramKey;
    final desc = (limits?['desc'] as String?) ?? hint;

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
              'Clamp: ${minVal.toStringAsFixed(2)} – ${maxVal.toStringAsFixed(2)} $unit',
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
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(
                state.isSaving
                    ? 'Saving to Robot...'
                    : state.isDirty
                        ? 'Save to Robot Database *'
                        : 'Saved to Robot',
              ),
              onPressed: state.isSaving || !state.isDirty ? null : _handleSave,
            ),
          ),
        ],
      ),
    );
  }
}
