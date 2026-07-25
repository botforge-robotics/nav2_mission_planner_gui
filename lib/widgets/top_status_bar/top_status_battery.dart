import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:sensor_msgs/msg.dart' as sensor_msgs;
import '../../providers/connection_provider.dart';

/// Battery % from `/battery/state` (sensor_msgs/BatteryState.percentage).
class TopStatusBattery extends StatefulWidget {
  final double height;
  final Color accentColor;

  const TopStatusBattery({
    super.key,
    required this.height,
    required this.accentColor,
  });

  @override
  State<TopStatusBattery> createState() => _TopStatusBatteryState();
}

class _TopStatusBatteryState extends State<TopStatusBattery> {
  Subscriber<sensor_msgs.BatteryState>? _sub;
  double? _percent; // 0–100
  bool _subscribed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final conn = Provider.of<ConnectionProvider>(context);
    if (conn.isConnected && !_subscribed) {
      _subscribe(conn);
    } else if (!conn.isConnected && _subscribed) {
      _unsubscribe();
    }
  }

  void _subscribe(ConnectionProvider conn) {
    try {
      _sub?.shutdown();
      _sub = Subscriber<sensor_msgs.BatteryState>(
        name: '/battery/state',
        type: sensor_msgs.BatteryState().fullType,
        ros2: conn.ros2Client,
        prototype: sensor_msgs.BatteryState(),
        callback: (msg) {
          // ROS BatteryState.percentage is usually 0.0–1.0; some stacks use 0–100.
          var p = msg.percentage;
          if (p.isNaN || p < 0) return;
          if (p <= 1.0) p *= 100.0;
          if (p > 100.0) p = 100.0;
          if (!mounted) return;
          setState(() => _percent = p);
        },
      );
      _subscribed = true;
    } catch (_) {
      _subscribed = false;
    }
  }

  void _unsubscribe() {
    _sub?.shutdown();
    _sub = null;
    _subscribed = false;
    if (mounted) setState(() => _percent = null);
  }

  @override
  void dispose() {
    _sub?.shutdown();
    super.dispose();
  }

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
    final conn = Provider.of<ConnectionProvider>(context);
    if (!conn.isConnected) return const SizedBox.shrink();

    final p = _percent;
    final color = p == null ? Colors.white54 : _batteryColor(p);
    final label = p == null ? '—' : '${p.round()}%';

    return Container(
      height: widget.height * 0.7,
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
