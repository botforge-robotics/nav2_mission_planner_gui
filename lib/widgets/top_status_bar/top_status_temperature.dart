import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nav2_mission_planner/providers/connection_provider.dart';
import 'package:nav2_mission_planner/providers/live_telemetry_provider.dart';

/// CPU + battery temperatures for the status bar, beside the battery level.
///
/// CPU comes from `/system/cpu_temperature` (navpromini_controller's
/// system_monitor_node); battery is the hottest cell, read from the scalar
/// `temperature` field of the `/battery/state` message [TopStatusBattery]
/// also reads — both now come from the shared [LiveTelemetryProvider]
/// instead of each widget opening its own `/battery/state` subscription.
///
/// Thresholds are deliberately different for the two: the Pi throttles around
/// 85degC (and this robot idles near 82degC), whereas a Li-ion pack is already
/// unhappy well before that.
///
/// Split so the two can be placed apart in the bar: battery temperature sits
/// beside the battery percentage (they describe the same thing and read as one
/// group), while CPU temperature goes to the far right where it does not
/// interrupt them.
enum TempKind { cpu, battery }

class TopStatusTemperature extends StatelessWidget {
  final double height;
  final Color accentColor;
  final TempKind kind;

  const TopStatusTemperature({
    super.key,
    required this.height,
    required this.accentColor,
    required this.kind,
  });

  // Pi 4/5 throttles ~85degC; warn a little before that.
  Color _cpuColor(double c) {
    if (c >= 80) return Colors.redAccent;
    if (c >= 70) return Colors.orangeAccent;
    return Colors.greenAccent;
  }

  Color _battColor(double c) {
    if (c >= 55) return Colors.redAccent;
    if (c >= 45) return Colors.orangeAccent;
    return Colors.greenAccent;
  }

  Widget _reading(IconData icon, double? value, Color Function(double) colorOf,
      String tooltip) {
    final color = value == null ? Colors.white54 : colorOf(value);
    final label = value == null ? '—' : '${value.round()}°C';
    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isConnected =
        context.select<ConnectionProvider, bool>((conn) => conn.isConnected);
    if (!isConnected) return const SizedBox.shrink();

    final bool isCpu = kind == TempKind.cpu;
    final value = isCpu
        ? context.select<LiveTelemetryProvider, double?>((t) => t.cpuTempC)
        : context.select<LiveTelemetryProvider, double?>((t) => t.batteryTempC);

    return Container(
      height: height * 0.7,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      margin: const EdgeInsets.only(right: 4),
      child: isCpu
          ? _reading(Icons.memory, value, _cpuColor, 'CPU temperature')
          : _reading(
              Icons.thermostat, value, _battColor, 'Battery temperature'),
    );
  }
}
