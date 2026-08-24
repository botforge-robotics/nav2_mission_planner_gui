import 'dart:async';
import 'package:nav_msgs/msg.dart' as nav_msgs;
import 'package:ros2_api/ros2_api.dart';
import 'package:nav2_mission_planner/providers/connection_provider.dart';

/// Owns navigation_screen.dart's `/plan`-style path subscription (subsystem
/// (g) in the extraction map): `_pathSubscriber`, `_currentPathTopic`,
/// `_pathSubscribed`, and the `_pathController` stream, extracted verbatim.
///
/// Unlike [NavigationOdometryController], this is a plain object rather
/// than a `ChangeNotifier` — nothing needs a screen rebuild when new path
/// data arrives; `OccupancyGridViewer` consumes [pathStream] directly, same
/// as it did when the stream lived on the screen. [isSubscribed] is a plain
/// getter read synchronously inside the screen's existing
/// `Consumer<MissionExecutionService>` block, which is already invoked on
/// every relevant rebuild — no separate listener wiring needed for that.
///
/// Subscribe/unsubscribe is still driven both imperatively (goal/settings
/// handlers) *and* reactively from inside `build()`'s
/// `Consumer<MissionExecutionService>` — that dual trigger is preserved at
/// the call site in navigation_screen.dart, not something this controller
/// changes.
class NavigationPathController {
  Subscriber<nav_msgs.Path>? _pathSubscriber;
  String? _currentPathTopic;
  bool _pathSubscribed = false;

  final _pathStreamController =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  Stream<List<Map<String, dynamic>>> get pathStream =>
      _pathStreamController.stream;
  bool get isSubscribed => _pathSubscribed;

  Future<void> subscribe({
    required ConnectionProvider connection,
    required String pathTopic,
  }) async {
    // Deliberately outside the try block below, matching the original
    // inline code exactly — if not connected, this throws uncaught rather
    // than being silently swallowed (unlike the odometry controller's
    // subscribe calls, where the equivalent access sits inside the try).
    final ros2 = connection.ros2Client;

    // If already subscribed to the desired topic, do nothing
    if (_pathSubscribed && _currentPathTopic == pathTopic) {
      return;
    }

    // Otherwise unsubscribe first
    unsubscribe();

    try {
      final subscriber = Subscriber<nav_msgs.Path>(
        name: pathTopic,
        type: nav_msgs.Path().fullType,
        ros2: ros2,
        callback: _handlePathMessage,
        prototype: nav_msgs.Path(),
      );
      _pathSubscriber = subscriber;
      _currentPathTopic = pathTopic;
      _pathSubscribed = true;
    } catch (e) {
      // Silent error handling
    }
  }

  void _handlePathMessage(nav_msgs.Path message) {
    // Convert PoseStamped list to JSON
    final List<Map<String, dynamic>> posesJson = message.poses.map((pose) {
      return {
        'position': {
          'x': pose.pose.position.x,
          'y': pose.pose.position.y,
          'z': pose.pose.position.z,
        },
        'orientation': {
          'x': pose.pose.orientation.x,
          'y': pose.pose.orientation.y,
          'z': pose.pose.orientation.z,
          'w': pose.pose.orientation.w,
        },
      };
    }).toList();

    _pathStreamController.add(posesJson);
  }

  void unsubscribe() {
    _pathSubscriber?.shutdown();
    _pathSubscriber = null;
    _pathSubscribed = false;
    _currentPathTopic = null;

    // Clear any existing path data so UI immediately removes path overlay
    _pathStreamController.add([]);
  }

  /// Matches the original screen's `dispose()`, which closed
  /// `_pathController` (unlike the odometry subscribers, this one *was*
  /// cleaned up on screen dispose) but did not shut down `_pathSubscriber`
  /// itself there either — preserved as-is.
  void disposeStream() {
    _pathStreamController.close();
  }
}
