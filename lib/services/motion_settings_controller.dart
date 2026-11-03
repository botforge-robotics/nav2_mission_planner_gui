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
  /// Automatically re-computes acceleration and deceleration using formulas:
  ///   - linear_accel = max_linear_speed / 4.0
  ///   - linear_decel = -max_linear_speed / 2.0 (-2 * linear_accel)
  ///   - angular_accel = max_angular_speed * 1.67
  void updateParam(String key, double val) {
    final updated = Map<String, double>.from(value.settings);
    updated[key] = val;

    if (key == 'max_linear_speed') {
      updated['linear_accel'] = double.parse((val / 4.0).toStringAsFixed(3));
      updated['linear_decel'] = double.parse((-val / 2.0).toStringAsFixed(3));
    } else if (key == 'max_angular_speed') {
      updated['angular_accel'] = double.parse((val * 1.67).toStringAsFixed(2));
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
