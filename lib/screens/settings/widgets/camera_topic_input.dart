import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ros2_api/ros2_api.dart';
import '../../../../providers/connection_provider.dart';
import '../../../../providers/settings_provider.dart';
import 'package:rosapi_msgs/srv.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraTopicInput extends StatefulWidget {
  final String initialValue;
  final Function(String) onChanged;
  final Size screenSize;
  final Color modeColor;
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;

  const CameraTopicInput({
    super.key,
    required this.initialValue,
    required this.onChanged,
    required this.screenSize,
    required this.modeColor,
    required this.enabled,
    required this.onEnabledChanged,
  });

  @override
  State<CameraTopicInput> createState() => _CameraTopicInputState();
}

class _CameraTopicInputState extends State<CameraTopicInput> {
  // Static list to maintain topics across widget instances
  static List<String> _sessionTopics = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Only fetch if we haven't fetched before in this session
    if (_sessionTopics.isEmpty) {
      _fetchTopics();
    }

    // If the camera is already enabled, ensure we have the required
    // permission as soon as the widget is built. Requesting it upfront
    // avoids problems later while a mission is running.
    if (widget.enabled) {
      // Delay until after build so that context is fully available.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleToggle(true);
      });
    }
  }

  Future<void> _fetchTopics() async {
    final connectionProvider = context.read<ConnectionProvider>();
    final settings = context.read<SettingsProvider>();
    final double timeoutSeconds = settings.communicationTimeout.toDouble();
    final ros2 = connectionProvider.ros2Client;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = ServiceClient<TopicsForType, TopicsForTypeRequest,
          TopicsForTypeResponse>(
        ros2: ros2!,
        name: '/rosapi/topics_for_type',
        type: TopicsForType().fullType,
        serviceType: TopicsForType(),
        timeout: timeoutSeconds,
      );

      final response = await client
          .call(TopicsForTypeRequest(type: 'sensor_msgs/msg/CompressedImage'));

      final topics = response.topics.where((t) => t.isNotEmpty).toList();

      // Auto-select logic
      String? selectedTopic;
      if (topics.contains(widget.initialValue)) {
        selectedTopic = widget.initialValue;
      }

      setState(() {
        _sessionTopics = topics; // Update the static list
        if (selectedTopic != null) {
          widget.onChanged(selectedTopic);
        }
      });
    } catch (e) {
      setState(() => _errorMessage = 'Failed to fetch topics: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildTopicDropdown(),
            ),
            SizedBox(width: 10),
            Column(
              children: [
                Text(
                  'Enable Camera',
                  style: TextStyle(
                    fontSize: widget.screenSize.height * 0.018,
                    color: Colors.grey.shade400,
                  ),
                ),
                // Intercept toggle to request storage permission when enabling camera
                Switch(
                  value: widget.enabled,
                  onChanged: (value) {
                    _handleToggle(value);
                  },
                  activeColor: widget.modeColor,
                ),
              ],
            ),
          ],
        ),
        Text(
          'Type: sensor_msgs/msg/CompressedImage',
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey.shade400,
            fontStyle: FontStyle.italic,
          ),
        ),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _errorMessage!,
              style: TextStyle(
                color: Colors.red,
                fontSize: 10,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTopicDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.modeColor.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Theme(
              data: Theme.of(context).copyWith(
                inputDecorationTheme: InputDecorationTheme(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: ButtonTheme(
                  alignedDropdown: true,
                  child: DropdownButton<String>(
                    value: _sessionTopics.contains(widget.initialValue)
                        ? widget.initialValue
                        : null,
                    items: [
                      if (_sessionTopics.isEmpty)
                        DropdownMenuItem(
                          value: '',
                          enabled: false,
                          child: Text(
                            'No topics found',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        )
                      else
                        ..._sessionTopics.map((topic) => DropdownMenuItem(
                              value: topic,
                              child: Text(
                                topic,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            )),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        widget.onChanged(value);
                      }
                    },
                    isExpanded: true,
                    icon: Icon(
                      Icons.arrow_drop_down,
                      color: widget.modeColor,
                    ),
                    hint: Text(
                      _isLoading ? 'Loading topics...' : 'Select topic',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                    dropdownColor: Colors.grey[850],
                    menuMaxHeight: 150,
                  ),
                ),
              ),
            ),
          ),
          Container(
            height: 42,
            width: 1,
            color: widget.modeColor.withOpacity(0.3),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _isLoading ? null : _fetchTopics,
              borderRadius: BorderRadius.horizontal(right: Radius.circular(7)),
              child: Container(
                width: 42,
                height: 42,
                padding: EdgeInsets.all(8),
                child: _isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(widget.modeColor),
                        ),
                      )
                    : Icon(
                        Icons.refresh_rounded,
                        size: 24,
                        color: widget.modeColor,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper to request the required permission before enabling camera
  Future<void> _handleToggle(bool enable) async {
    if (!enable) {
      widget.onEnabledChanged(false);
      return;
    }

    bool granted = await _requestStoragePermission();

    if (granted) {
      widget.onEnabledChanged(true);
    } else {
      widget.onEnabledChanged(false);
    }
  }

  Future<bool> _requestStoragePermission() async {
    // Start with the platform-appropriate primary permission
    Permission permission = Permission.storage;

    if (Theme.of(context).platform == TargetPlatform.iOS) {
      permission = Permission.photosAddOnly;
    }

    // For Android 13+ storage permission maps to READ_MEDIA_IMAGES which is
    // exposed via Permission.photos. If the regular storage permission is
    // denied we will fallback to requesting photos.

    // Helper that actually asks the OS.
    Future<PermissionStatus> ask(Permission p) async {
      if (await p.isGranted) return PermissionStatus.granted;
      return p.request();
    }

    PermissionStatus status = await ask(permission);

    if (status.isDenied || status.isRestricted) {
      // Try fallback photos permission (Android 13) only if we haven't tried it
      if (permission != Permission.photos &&
          permission != Permission.photosAddOnly) {
        status = await ask(Permission.photos);
      }
    }

    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      // Offer to open app settings so user can enable manually
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            action: SnackBarAction(
              label: 'Settings',
              onPressed: openAppSettings,
            ),
            content: const Text(
                'Camera image saving requires permission. Enable it in settings.'),
            backgroundColor: Colors.red.withOpacity(0.9),
          ),
        );
      }
    } else {
      // Simple denial (not permanent) – silently keep disabled.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Permission denied – camera disabled.'),
            backgroundColor: Colors.red.withOpacity(0.9),
          ),
        );
      }
    }

    return false;
  }
}
