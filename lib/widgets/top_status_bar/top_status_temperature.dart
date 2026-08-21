import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:sensor_msgs/msg.dart' as sensor_msgs;
import 'package:std_msgs/msg.dart' as std_msgs;
import '../../providers/connection_provider.dart';

/// CPU + battery temperatures for the status bar, beside the battery level.
///
/// CPU comes from `/system/cpu_temperature` (navpromini_controller's
/// system_monitor_node); battery is the hottest cell, read from the scalar
/// `temperature` field of the `/battery/state` message the battery widget
/// already consumes — battery_node fills it from the Daly BMS.
///
/// Thresholds are deliberately different for the two: the Pi throttles around
/// 85degC (and this robot idles near 82degC), whereas a Li-ion pack is already
/// unhappy well before that.
/// Which reading this instance renders.
///
/// Split so the two can be placed apart in the bar: battery temperature sits
/// beside the battery percentage (they describe the same thing and read as one
/// group), while CPU temperature goes to the far right where it does not
/// interrupt them.
enum TempKind { cpu, battery }

class TopStatusTemperature extends StatefulWidget {
  final double height;
  final Color accentColor;
  final TempKind kind;

  const TopStatusTemperature({
    super.key,
    required this.height,
    required this.accentColor,
    required this.kind,
  });

  @override
  State<TopStatusTemperature> createState() => _TopStatusTemperatureState();
}

class _TopStatusTemperatureState extends State<TopStatusTemperature> {
  Subscriber<std_msgs.Float32>? _cpuSub;
  Subscriber<sensor_msgs.BatteryState>? _battSub;
  double? _cpuC;
  double? _battC;
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
      if (widget.kind == TempKind.battery) {
        _subscribeBattery(conn);
        _subscribed = true;
        return;
      }
      _cpuSub?.shutdown();
      _cpuSub = Subscriber<std_msgs.Float32>(
        name: '/system/cpu_temperature',
        type: std_msgs.Float32().fullType,
        ros2: conn.ros2Client,
        prototype: std_msgs.Float32(),
        callback: (msg) {
          final v = msg.data;
          if (v.isNaN || !mounted) return;
          setState(() => _cpuC = v);
        },
      );

      _subscribed = true;
    } catch (_) {
      _subscribed = false;
    }
  }

  void _subscribeBattery(ConnectionProvider conn) {
    try {
      _battSub?.shutdown();
      _battSub = Subscriber<sensor_msgs.BatteryState>(
        name: '/battery/state',
        type: sensor_msgs.BatteryState().fullType,
        ros2: conn.ros2Client,
        prototype: sensor_msgs.BatteryState(),
        callback: (msg) {
          final v = msg.temperature;
          // Packs that don't report temperature leave this 0.0/NaN — don't
          // render a bogus 0degC reading in that case.
          if (v.isNaN || v == 0.0 || !mounted) return;
          setState(() => _battC = v);
        },
      );
      _subscribed = true;
    } catch (_) {
      _subscribed = false;
    }
  }

  void _unsubscribe() {
    _cpuSub?.shutdown();
    _cpuSub = null;
    _battSub?.shutdown();
    _battSub = null;
    _subscribed = false;
    if (mounted) {
      setState(() {
        _cpuC = null;
        _battC = null;
      });
    }
  }

  @override
  void dispose() {
    _cpuSub?.shutdown();
    _battSub?.shutdown();
    super.dispose();
  }

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
    final conn = Provider.of<ConnectionProvider>(context);
    if (!conn.isConnected) return const SizedBox.shrink();

    final bool isCpu = widget.kind == TempKind.cpu;
    return Container(
      height: widget.height * 0.7,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      margin: const EdgeInsets.only(right: 4),
      child: isCpu
          ? _reading(Icons.memory, _cpuC, _cpuColor, 'CPU temperature')
          : _reading(
              Icons.thermostat, _battC, _battColor, 'Battery temperature'),
    );
  }
}
