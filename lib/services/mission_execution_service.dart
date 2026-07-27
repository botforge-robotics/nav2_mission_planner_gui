import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nav2_mission_planner/modals/mission.dart';
import 'package:nav2_mission_planner/services/goal_service.dart';
// Provider can be added later if ROS2 interaction is integrated
import '../helpers/conversions.dart';
import 'package:provider/provider.dart';
import 'package:nav2_mission_planner/providers/connection_provider.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensor_msgs/msg.dart' as sensor_msgs;
import 'dart:typed_data';
import 'package:nav2_mission_planner/providers/settings_provider.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:http/http.dart' as http;

/// Holds live information about mission execution progress
class MissionProgress {
  final Mission mission;
  final int currentIndex;
  final bool isRunning;
  final bool isPaused;
  final String? errorMessage;

  const MissionProgress({
    required this.mission,
    required this.currentIndex,
    required this.isRunning,
    required this.isPaused,
    this.errorMessage,
  });

  int get totalItems => mission.items.length;
  MissionItem? get currentItem =>
      (currentIndex >= 0 && currentIndex < mission.items.length)
          ? mission.items[currentIndex]
          : null;
}

/// Executes a [Mission] item-by-item.  Supports pause/resume/cancel and
/// streams live [MissionProgress] updates for UI widgets.
class MissionExecutionService extends ChangeNotifier {
  Mission? _mission;
  int _currentIndex = 0;
  bool _isRunning = false;
  bool _isPaused = false;
  String? _error;

  // Additional state tracking for UI feedback
  double? _distanceRemaining;
  double? _waitTimeRemaining;
  bool _isWaitingForResponse = false;
  bool _isWaitingForResult = false;

  final StreamController<MissionProgress> _progressController =
      StreamController.broadcast();

  Stream<MissionProgress> get progressStream => _progressController.stream;

  Mission? get currentMission => _mission;
  bool get isRunning => _isRunning;
  bool get isPaused => _isPaused;
  int get currentIndex => _currentIndex;
  String? get errorMessage => _error;

  // Getters for detailed execution state
  double? get distanceRemaining => _distanceRemaining;
  double? get waitTimeRemaining => _waitTimeRemaining;
  bool get isWaitingForResponse => _isWaitingForResponse;
  bool get isWaitingForResult => _isWaitingForResult;

  // Keep reference to active goal client so we can cancel cleanly
  GoalService? _activeGoalService;

  // Keep track of active periodic publishers to cancel when needed
  final List<Timer> _activePublishTimers = [];

  /// Starts executing [mission].  If another mission is already running it will
  /// be ignored.
  Future<void> startMission(BuildContext context, Mission mission) async {
    if (_isRunning) return;

    _mission = mission;
    _currentIndex = 0;
    _isRunning = true;
    _isPaused = false;
    _error = null;
    _resetExecutionState();
    _broadcast();

    try {
      while (_isRunning && _currentIndex < mission.items.length) {
        // wait if paused
        if (_isPaused) {
          await Future.delayed(const Duration(milliseconds: 200));
          continue;
        }

        final item = mission.items[_currentIndex];
        final success = await _executeMissionItem(context, item);
        if (!success) {
          _error = 'Failed to execute item ${_currentIndex + 1}';
          _isRunning = false;
          _broadcast();
          return;
        }

        _currentIndex++;
        _broadcast();
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isRunning = false;
      _isPaused = false;

      // Ensure any background publishers are stopped when mission finishes
      _cancelActivePublishers();

      _broadcast();
    }
  }

  void pause() {
    if (!_isRunning) return;
    _isPaused = true;
    _broadcast();
  }

  void resume() {
    if (!_isRunning) return;
    _isPaused = false;
    _broadcast();
  }

  void cancel() {
    _isRunning = false;
    _isPaused = false;

    // Cancel any active navigation goal via stored client
    try {
      _activeGoalService?.cancelCurrentGoal();
    } catch (_) {}
    _activeGoalService = null;

    // Cancel all active periodic publishers – used when mission cancelled/finished
    _cancelActivePublishers();

    _broadcast();
  }

  Future<bool> _executeMissionItem(
      BuildContext context, MissionItem item) async {
    _resetExecutionState();

    switch (item.type) {
      case MissionItemType.goto:
        if (item.position == null) return true; // nothing to do

        // Real distance updates via action feedback
        _activeGoalService = GoalService();
        _activeGoalService!.initialize(context: context);

        final result = await _activeGoalService!.sendGoal(
          x: item.position!.x,
          y: item.position!.y,
          orientation: eulerToQuaternion(0, 0, item.position!.theta),
          frameId: 'map',
          feedbackHandler: (feedback) {
            // Update distance remaining from feedback.  The NavigateToPose
            // feedback message contains a `distance_remaining` field giving the
            // straight-line distance left to the goal in metres.
            if (_currentIndexItemSame(item)) {
              _distanceRemaining = feedback.distance_remaining;
              _broadcast();
            }
          },
        );

        // Clear distance once goal finished (success or failure)
        _distanceRemaining = null;
        // Clear active goal client when done
        _activeGoalService = null;
        return result != null;

      case MissionItemType.wait:
        final totalSecs = item.waitDuration ?? 0;
        _waitTimeRemaining = totalSecs;
        _broadcast();

        // Update remaining time during wait
        final stepMs = 100;
        for (int i = 0; i < totalSecs * 1000; i += stepMs) {
          if (!_isRunning || _isPaused) break;

          await Future.delayed(Duration(milliseconds: stepMs));
          _waitTimeRemaining = totalSecs - (i + stepMs) / 1000;
          _broadcast();
        }

        _waitTimeRemaining = null;
        return true;

      case MissionItemType.publish:
        return await _handlePublish(context, item);

      case MissionItemType.callService:
        return await _handleServiceCall(context, item);

      case MissionItemType.callAction:
        return await _handleActionCall(context, item);

      case MissionItemType.captureImage:
        return await _handleCaptureImage(context, item);

      case MissionItemType.apiCall:
        return await _handleApiCall(context, item);
    }
  }

  Future<bool> _handlePublish(BuildContext context, MissionItem item) async {
    final conn = Provider.of<ConnectionProvider>(context, listen: false);
    final ros2 = conn.ros2Client;
    if (!conn.isConnected) return false;

    // Validate required fields
    if (item.publishTopic == null || item.publishMsgType == null) return false;

    // Extract publish parameters with sensible defaults
    final freqType = item.publishFrequencyType ?? 'once';
    final hz = (item.publishFrequency ?? 1).clamp(0.1, 1000);

    // Use DynamicPublisher from ros2_api library
    final publisher = DynamicPublisher(
      ros2: ros2,
      topicName: item.publishTopic!,
      topicType: item.publishMsgType!,
    );

    // Helper to publish once
    void publishOnce() {
      publisher.publish(item.publishMessage ?? {});
    }

    switch (freqType) {
      case 'once':
        publishOnce();
        break;

      // Legacy or explicit Hz option
      case 'hz':
      case 'duration':
      case 'frequency':
        // For consistency we treat all these the same and look at publishDuration.

        // Specific duration (>0): block execution until time elapses
        if (item.publishDuration != null && item.publishDuration! > 0) {
          final periodMs = (1000 / hz).round();
          final totalMs = (item.publishDuration! * 1000).round();
          for (int elapsed = 0; elapsed < totalMs; elapsed += periodMs) {
            if (!_isRunning || _isPaused) break;
            publishOnce();
            await Future.delayed(Duration(milliseconds: periodMs));
          }
          break;
        }

        // Mission end (duration == -1) => keep publishing until mission stops
        if (item.publishDuration != null && item.publishDuration == -1) {
          final periodMs = (1000 / hz).round();
          Timer? timer;
          timer = Timer.periodic(Duration(milliseconds: periodMs), (t) {
            if (!_isRunning || _isPaused) {
              return; // still running but maybe paused
            }
            if (!_isRunning) {
              // Mission finished, stop timer
              t.cancel();
              _activePublishTimers.remove(t);
              publisher.unadvertise();
              return;
            }
            publishOnce();
          });
          _activePublishTimers.add(timer);
          // Do not block – continue to next mission item
          return true;
        }

        // Until next waypoint (publishDuration == null)
        {
          final periodMs = (1000 / hz).round();

          // Determine index of the next GOTO item *after* this publish item
          int nextGotoIndex = -1;
          if (_mission != null) {
            for (int i = _currentIndex + 1; i < _mission!.items.length; i++) {
              if (_mission!.items[i].type == MissionItemType.goto) {
                nextGotoIndex = i;
                break;
              }
            }
          }

          Timer? timer;
          timer = Timer.periodic(Duration(milliseconds: periodMs), (t) {
            if (!_isRunning) {
              t.cancel();
              _activePublishTimers.remove(t);
              publisher.unadvertise();
              return;
            }

            if (_isPaused) {
              return; // Skip publishing while paused
            }

            // If we have passed the next GOTO (or no future goto exists and mission ended), stop
            if (nextGotoIndex != -1 && _currentIndex > nextGotoIndex) {
              t.cancel();
              _activePublishTimers.remove(t);
              publisher.unadvertise();
              return;
            }

            publishOnce();
          });

          _activePublishTimers.add(timer);
          // Do not block execution – move to next item immediately
          return true;
        }

      default:
        publishOnce();
    }

    // Unadvertise after blocking publish loop finishes
    publisher.unadvertise();

    return true;
  }

  Future<bool> _handleServiceCall(
      BuildContext context, MissionItem item) async {
    final conn = Provider.of<ConnectionProvider>(context, listen: false);
    final ros2 = conn.ros2Client;
    if (!conn.isConnected) return false;

    if (item.serviceName == null) return false;

    if (item.waitForServiceResponse == true) {
      _isWaitingForResponse = true;
      _broadcast();
    }

    try {
      // Use DynamicServiceClient from ros2_api library
      final serviceClient = DynamicServiceClient(
        ros2: ros2,
        serviceName: item.serviceName!,
        serviceType: item.serviceType ?? '',
      );

      final result = await serviceClient.call(
        requestArgs: item.serviceRequest ?? {},
        timeout: const Duration(minutes: 5),
      );

      final success = result != null;

      _isWaitingForResponse = false;
      _broadcast();
      return success;
    } catch (e) {
      _isWaitingForResponse = false;
      _broadcast();
      return false;
    }
  }

  Future<bool> _handleActionCall(BuildContext context, MissionItem item) async {
    final conn = Provider.of<ConnectionProvider>(context, listen: false);
    final ros2 = conn.ros2Client;
    if (!conn.isConnected) return false;

    if (item.actionName == null) return false;

    if (item.waitForActionResult == true) {
      _isWaitingForResult = true;
      _broadcast();
    }

    try {
      // Use DynamicActionClient from ros2_api library
      final actionClient = DynamicActionClient(
        ros2: ros2,
        actionName: item.actionName!,
        actionType: item.actionType ?? '',
      );

      final result = await actionClient.send(
        goalArgs: item.actionGoal ?? {},
        timeout: const Duration(minutes: 5),
        onFeedback: (feedback) {
          // Handle action feedback if needed
          // This could be used to update UI with progress information
        },
      );

      final success = result != null;

      _isWaitingForResult = false;
      _broadcast();
      return success;
    } catch (e) {
      _isWaitingForResult = false;
      _broadcast();
      return false;
    }
  }

  Future<bool> _handleApiCall(BuildContext context, MissionItem item) async {
    final url = item.apiUrl?.trim();
    if (url == null || url.isEmpty) return false;

    final method = (item.apiMethod ?? 'POST').toUpperCase();
    final waitForResponse = item.apiWaitForResponse ?? true;
    final headers = <String, String>{
      if (item.apiHeaders != null) ...item.apiHeaders!,
    };
    final body = item.apiBody;

    // Default JSON content-type when sending a body and none is set
    if (body != null &&
        body.isNotEmpty &&
        method != 'GET' &&
        method != 'DELETE' &&
        !headers.keys.any((k) => k.toLowerCase() == 'content-type')) {
      headers['Content-Type'] = 'application/json';
    }

    Uri uri;
    try {
      uri = Uri.parse(url);
    } catch (_) {
      try {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('API Call failed: invalid URL'),
            backgroundColor: Colors.red.withOpacity(0.9),
          ),
        );
      } catch (_) {}
      return false;
    }

    Future<http.Response> sendRequest() {
      switch (method) {
        case 'GET':
          return http.get(uri, headers: headers);
        case 'PUT':
          return http.put(uri, headers: headers, body: body);
        case 'PATCH':
          return http.patch(uri, headers: headers, body: body);
        case 'DELETE':
          return http.delete(uri, headers: headers, body: body);
        case 'POST':
        default:
          return http.post(uri, headers: headers, body: body);
      }
    }

    if (!waitForResponse) {
      // Fire-and-forget; do not block mission execution
      unawaited(sendRequest().then((response) {
        try {
          final ok = response.statusCode >= 200 && response.statusCode < 300;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(ok
                  ? 'API Call succeeded (${response.statusCode})'
                  : 'API Call failed (${response.statusCode})'),
              backgroundColor:
                  (ok ? Colors.green : Colors.red).withOpacity(0.9),
            ),
          );
        } catch (_) {}
      }).catchError((e) {
        try {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('API Call failed: $e'),
              backgroundColor: Colors.red.withOpacity(0.9),
            ),
          );
        } catch (_) {}
      }));
      return true;
    }

    _isWaitingForResponse = true;
    _broadcast();

    try {
      final response = await sendRequest().timeout(
        const Duration(seconds: 30),
      );
      final ok = response.statusCode >= 200 && response.statusCode < 300;

      try {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok
                ? 'API Call succeeded (${response.statusCode})'
                : 'API Call failed (${response.statusCode})'),
            backgroundColor: (ok ? Colors.green : Colors.red).withOpacity(0.9),
          ),
        );
      } catch (_) {}

      _isWaitingForResponse = false;
      _broadcast();
      return ok;
    } on TimeoutException {
      try {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('API Call timed out after 30s'),
            backgroundColor: Colors.red.withOpacity(0.9),
          ),
        );
      } catch (_) {}
      _isWaitingForResponse = false;
      _broadcast();
      return false;
    } catch (e) {
      try {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('API Call failed: $e'),
            backgroundColor: Colors.red.withOpacity(0.9),
          ),
        );
      } catch (_) {}
      _isWaitingForResponse = false;
      _broadcast();
      return false;
    }
  }

  Future<bool> _handleCaptureImage(
      BuildContext context, MissionItem item) async {
    final conn = Provider.of<ConnectionProvider>(context, listen: false);
    final ros2 = conn.ros2Client;
    if (!conn.isConnected) return false;

    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final topic = settings.cameraImageTopic;

    if (topic.isEmpty) return false;

    try {
      // Request storage/photos permission (Android 13+, iOS)
      Permission permission = Permission.storage;
      if (Theme.of(context).platform == TargetPlatform.iOS) {
        permission = Permission.photosAddOnly;
      }

      Future<PermissionStatus> ask(Permission p) async {
        if (await p.isGranted) return PermissionStatus.granted;
        return p.request();
      }

      PermissionStatus status = await ask(permission);
      if (status.isDenied || status.isRestricted) {
        if (permission != Permission.photos &&
            permission != Permission.photosAddOnly) {
          status = await ask(Permission.photos);
        }
      }

      if (!status.isGranted) {
        return false;
      }

      // Wait for a single compressed image message
      final completer = Completer<sensor_msgs.CompressedImage?>();
      late Subscriber<sensor_msgs.CompressedImage> sub;
      sub = Subscriber<sensor_msgs.CompressedImage>(
        name: topic,
        type: sensor_msgs.CompressedImage().fullType,
        ros2: ros2,
        callback: (msg) {
          if (!completer.isCompleted) {
            completer.complete(msg);
          }
        },
        prototype: sensor_msgs.CompressedImage(),
      );

      // Wait for first frame or timeout
      final imgMsg = await completer.future
          .timeout(const Duration(seconds: 5), onTimeout: () => null);

      // Clean up subscription
      sub.shutdown();

      if (imgMsg == null || imgMsg.data.isEmpty) return false;

      final bytes = Uint8List.fromList(imgMsg.data);
      final result = await ImageGallerySaver.saveImage(
        bytes,
        quality: 90,
        name: 'mission_${DateTime.now().millisecondsSinceEpoch}',
      );

      // Optionally show snackbar if context has ScaffoldMessenger
      try {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Image captured'),
            backgroundColor: Colors.green.withOpacity(0.9),
          ),
        );
      } catch (_) {}

      return result['isSuccess'] == true || result == true;
    } catch (_) {
      return false;
    }
  }

  bool _currentIndexItemSame(MissionItem item) {
    return _mission != null &&
        _currentIndex < _mission!.items.length &&
        identical(_mission!.items[_currentIndex], item);
  }

  void _broadcast() {
    if (_mission == null) return;
    _progressController.add(MissionProgress(
      mission: _mission!,
      currentIndex: _currentIndex,
      isRunning: _isRunning,
      isPaused: _isPaused,
      errorMessage: _error,
    ));
    notifyListeners();
  }

  // Reset all execution state variables
  void _resetExecutionState() {
    _distanceRemaining = null;
    _waitTimeRemaining = null;
    _isWaitingForResponse = false;
    _isWaitingForResult = false;
  }

  // Cancel all active periodic publishers – used when mission cancelled/finished
  void _cancelActivePublishers() {
    for (final t in List<Timer>.from(_activePublishTimers)) {
      t.cancel();
    }
    _activePublishTimers.clear();
  }

  @override
  void dispose() {
    _cancelActivePublishers();
    _progressController.close();
    super.dispose();
  }
}
