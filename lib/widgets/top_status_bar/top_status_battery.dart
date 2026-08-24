import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nav2_mission_planner/providers/connection_provider.dart';
import 'package:nav2_mission_planner/providers/live_telemetry_provider.dart';

/// Battery % from `/battery/state` (sensor_msgs/BatteryState.percentage),
/// sourced from the shared [LiveTelemetryProvider] rather than opening its
/// own subscription (that subscription used to be duplicated here and in
/// [TopStatusTemperature] — both now read the same one).
class TopStatusBattery extends StatelessWidget {
  final double height;
  final Color accentColor;

  const TopStatusBattery({
    super.key,
    required this.height,
    required this.accentColor,
  });

  Color _batteryColor(double p) {
    if (p <= 15) return Colors.redAccent;
    if (p <= 30) return Colors.orangeAccent;
    return Colors.greenAccent;
  }

  IconData _batteryIcon(double p) {
    if (p <= 15) return Icons.battery_alert;
    if (p <= 30) return Icons.battery_2_bar;
    if (p <= 60) return Icons.battery_5_bar;
    return Icons.battery_full;
  }

  @override
  Widget build(BuildContext context) {
    final isConnected =
        context.select<ConnectionProvider, bool>((conn) => conn.isConnected);
    if (!isConnected) return const SizedBox.shrink();

    final p =
        context.select<LiveTelemetryProvider, double?>((t) => t.batteryPercent);
    final color = p == null ? Colors.white54 : _batteryColor(p);
    final label = p == null ? '—' : '${p.round()}%';

    return Container(
      height: height * 0.7,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      margin: const EdgeInsets.only(right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            p == null ? Icons.battery_unknown : _batteryIcon(p),
            color: color,
            size: 14,
          ),
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
}
