import 'package:flutter/foundation.dart';
import 'sdk_api_service.dart';

class MotionSettingsState {
  final bool isLoading;
  final bool isSaving;
  final String? error;
  final Map<String, double> settings;
  final Map<String, double> defaults;
  final Map<String, dynamic> safetyLimits;
  final bool isDirty;

  const MotionSettingsState({
    this.isLoading = false,
    this.isSaving = false,
    this.error,
    this.settings = const {},
    this.defaults = const {},
    this.safetyLimits = const {},
    this.isDirty = false,
  });

  MotionSettingsState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? error,
    bool clearError = false,
    Map<String, double>? settings,
    Map<String, double>? defaults,
    Map<String, dynamic>? safetyLimits,
    bool? isDirty,
  }) {
    return MotionSettingsState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      error: clearError ? null : (error ?? this.error),
      settings: settings ?? this.settings,
      defaults: defaults ?? this.defaults,
      safetyLimits: safetyLimits ?? this.safetyLimits,
      isDirty: isDirty ?? this.isDirty,
    );
  }
}

/// Controller for robot dynamic motion & docking parameters.
/// The robot's SQLite database is the single source of truth.
/// The GUI holds no local truth; it fetches on mount and updates the robot.
class MotionSettingsController extends ValueNotifier<MotionSettingsState> {
  MotionSettingsController._() : super(const MotionSettingsState());

  static final instance = MotionSettingsController._();

  /// Loads current parameters directly from the robot SQLite database.
  Future<void> refresh(SdkApiService api) async {
    value = value.copyWith(isLoading: true, clearError: true);
    try {
      final res = await api.getMotionSettings();
      final rawSettings = (res['settings'] as Map?) ?? {};
      final rawDefaults = (res['defaults'] as Map?) ?? {};
      final rawLimits = (res['safety_limits'] as Map?) ?? {};

      final settings = <String, double>{};
      rawSettings.forEach((k, v) {
        if (v is num) settings[k.toString()] = v.toDouble();
      });

      final defaults = <String, double>{};
      rawDefaults.forEach((k, v) {
        if (v is num) defaults[k.toString()] = v.toDouble();
      });

      value = MotionSettingsState(
        isLoading: false,
        settings: settings,
        defaults: defaults,
        safetyLimits: Map<String, dynamic>.from(rawLimits),
        isDirty: false,
      );
    } catch (e) {
      value = value.copyWith(
        isLoading: false,
        error: 'Failed to load motion settings from robot: $e',
      );
    }
  }

  /// Updates a local parameter when the user adjusts a slider or taps +/-.
  /// - When adjusting max_linear_speed, linear_accel and linear_decel are auto-configured.
  /// - When adjusting max_angular_speed, angular_accel is auto-configured.
  void updateParam(String key, double val) {
    final updated = Map<String, double>.from(value.settings);
    updated[key] = val;

    if (key == 'max_linear_speed') {
      // Auto-configure linear acceleration and deceleration based on selected max linear speed
      // linear_accel = val / 1.6 (~0.25 m/s² for 0.40 m/s)
      // linear_decel = -val / 1.2 (~ -0.33 m/s² for 0.40 m/s)
      final rawAccel = (val / 1.6).clamp(0.05, 0.50);
      final rawDecel = (-val / 1.2).clamp(-0.60, -0.05);
      updated['linear_accel'] = double.parse(rawAccel.toStringAsFixed(3));
      updated['linear_decel'] = double.parse(rawDecel.toStringAsFixed(3));
    } else if (key == 'max_angular_speed') {
      // Auto-configure angular acceleration based on selected max angular speed
      // angular_accel = val * 2.5 (~1.63 rad/s² for 0.65 rad/s)
      final rawAngAccel = (val * 2.5).clamp(0.20, 2.50);
      updated['angular_accel'] = double.parse(rawAngAccel.toStringAsFixed(2));
    }

    value = value.copyWith(settings: updated, isDirty: true);
  }

  /// Persists settings to robot SQLite database and live ROS nodes.
  Future<bool> save(SdkApiService api) async {
    value = value.copyWith(isSaving: true, clearError: true);
    try {
      final res = await api.saveMotionSettings(value.settings);
      final rawSettings = (res['settings'] as Map?) ?? {};
      final settings = <String, double>{};
      rawSettings.forEach((k, v) {
        if (v is num) settings[k.toString()] = v.toDouble();
      });

      value = value.copyWith(
        isSaving: false,
        settings: settings,
        isDirty: false,
      );
      return true;
    } catch (e) {
      value = value.copyWith(
        isSaving: false,
        error: 'Failed to save settings to robot: $e',
      );
      return false;
    }
  }

  /// Restores all parameters to calibrated baseline defaults in robot DB.
  Future<bool> restoreDefaults(SdkApiService api) async {
    value = value.copyWith(isSaving: true, clearError: true);
    try {
      final res = await api.restoreMotionSettingsDefaults();
      final rawSettings = (res['settings'] as Map?) ?? {};
      final settings = <String, double>{};
      rawSettings.forEach((k, v) {
        if (v is num) settings[k.toString()] = v.toDouble();
      });

      value = value.copyWith(
        isSaving: false,
        settings: settings,
        isDirty: false,
      );
      return true;
    } catch (e) {
      value = value.copyWith(
        isSaving: false,
        error: 'Failed to restore defaults: $e',
      );
      return false;
    }
  }

  /// Sets present settings as the default speeds in the robot database.
  Future<bool> setCurrentAsDefault(SdkApiService api) async {
    value = value.copyWith(isSaving: true, clearError: true);
    try {
      final res = await api.setCurrentAsDefaultMotionSettings();
      final rawDefaults = (res['defaults'] as Map?) ?? {};
      final defaults = <String, double>{};
      rawDefaults.forEach((k, v) {
        if (v is num) defaults[k.toString()] = v.toDouble();
      });

      value = value.copyWith(
        isSaving: false,
        defaults: defaults,
      );
      return true;
    } catch (e) {
      value = value.copyWith(
        isSaving: false,
        error: 'Failed to set present settings as defaults: $e',
      );
      return false;
    }
  }
}
