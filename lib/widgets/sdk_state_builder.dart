import 'package:flutter/widgets.dart';

import '../services/sdk_state_service.dart';

/// Wraps [SdkStateService]'s poll in a builder that creates the underlying
/// stream exactly once per [robotIp] — not on every rebuild.
///
/// `StreamBuilder(stream: SdkStateService(ip).watch(), ...)` written inline
/// in a `build()` method looks right but isn't: `.watch()` returns a
/// brand-new `Stream` instance every call, so any *other* reason the
/// surrounding widget rebuilds (e.g. a `context.watch<ConnectionProvider>()`
/// or `RobotTelemetryProvider` tick — both fire far more often than this
/// poll's own 3s interval) makes `StreamBuilder` cancel the in-flight
/// subscription and start over. If rebuilds arrive faster than one
/// `fetchOnce()` HTTP round-trip, the first real value never lands and the
/// UI is stuck on [SdkState.unknown] forever — exactly what happened on the
/// Maps List screen (every map showed "Not currently active", including the
/// genuinely active one) while the Dashboard merely got lucky with an early
/// quiet window and kept showing its last good value afterwards. Caching the
/// stream instance in State, and only rebuilding it if [robotIp] itself
/// actually changes, sidesteps this entirely.
class SdkStateBuilder extends StatefulWidget {
  const SdkStateBuilder(
      {super.key, required this.robotIp, required this.builder});

  final String robotIp;
  final Widget Function(BuildContext context, SdkState state) builder;

  @override
  State<SdkStateBuilder> createState() => _SdkStateBuilderState();
}

class _SdkStateBuilderState extends State<SdkStateBuilder> {
  late String _ip;
  late Stream<SdkState> _stream;

  @override
  void initState() {
    super.initState();
    _ip = widget.robotIp;
    _stream = SdkStateService(_ip).watch();
  }

  @override
  void didUpdateWidget(covariant SdkStateBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.robotIp != _ip) {
      _ip = widget.robotIp;
      _stream = SdkStateService(_ip).watch();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SdkState>(
      initialData: SdkState.unknown,
      stream: _stream,
      builder: (context, snapshot) =>
          widget.builder(context, snapshot.data ?? SdkState.unknown),
    );
  }
}
