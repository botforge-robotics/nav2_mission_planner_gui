import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import '../../providers/connection_provider.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import 'dart:typed_data';
import 'package:ros2_api/ros2_api.dart';
import 'package:nav2_mission_planner/providers/settings_provider.dart';
import 'package:rosapi_msgs/srv.dart';

class ImageViewer extends StatefulWidget {
  final String topic;
  final bool enabled;
  final bool hideTopic;
  const ImageViewer({
    super.key,
    required this.topic,
    required this.enabled,
    this.hideTopic = false,
  });

  @override
  ImageViewerState createState() => ImageViewerState();
}

class ImageViewerState extends State<ImageViewer> {
  String _errorText = '';
  Uint8List? _currentFrame;
  final GlobalKey _frameKey = GlobalKey();

  // cache/topics state
  static List<String> _sessionTopics = [];
  bool _topicLoading = false;
  String? _topicError;

  Uint8List? get currentFrame => _currentFrame;

  @override
  void initState() {
    super.initState();
    _fetchTopics(); // prime the topic list on startup
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// Copied & adapted from CameraTopicInput._fetchTopics()
  Future<void> _fetchTopics() async {
    setState(() {
      _topicLoading = true;
      _topicError = null;
    });
    try {
      final ros2 =
          Provider.of<ConnectionProvider>(context, listen: false).ros2Client!;
      final client = ServiceClient<TopicsForType, TopicsForTypeRequest,
          TopicsForTypeResponse>(
        ros2: ros2,
        name: '/rosapi/topics_for_type',
        type: TopicsForType().fullType,
        serviceType: TopicsForType(),
      );
      final resp = await client.call(
        TopicsForTypeRequest(type: 'sensor_msgs/msg/CompressedImage'),
      );
      final topics = resp.topics.where((t) => t.isNotEmpty).toList();
      setState(() => _sessionTopics = topics);
    } catch (e) {
      setState(() => _topicError = 'Error fetching topics: $e');
    } finally {
      setState(() => _topicLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (!widget.enabled) {
        return Center(child: Text('Camera feed disabled'));
      }

      final connectionProvider = context.read<ConnectionProvider>();
      final robotIp = connectionProvider.ip;
      if (robotIp.isEmpty) {
        return Center(
            child: Text('No robot IP available',
                style: TextStyle(color: Colors.red)));
      }

      final streamUrl =
          'http://$robotIp:8081/stream?topic=${widget.topic.replaceAll(RegExp(r'/compressed$'), '')}&type=ros_compressed&default_transport=compressed';

      return Stack(
        children: [
          // --- MJPEG View or error indicator ---
          Container(
            child: _errorText.isNotEmpty
                ? Center(
                    child:
                        Text(_errorText, style: TextStyle(color: Colors.red)))
                : RepaintBoundary(
                    key: _frameKey,
                    child: Mjpeg(
                      stream: streamUrl,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      fit: BoxFit.contain,
                      timeout: const Duration(seconds: 5),
                      isLive: true,
                      loading: (context) => Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.white70),
                            const SizedBox(height: 16),
                            Text('Connecting to stream...',
                                style: TextStyle(color: Colors.white70)),
                          ],
                        ),
                      ),
                      error: (context, error, stack) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          setState(() => _errorText = 'Stream error: $error');
                        });
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.videocam_off,
                                  color: Colors.red.withOpacity(0.7), size: 48),
                              const SizedBox(height: 16),
                              Text('No video streaming\nCheck camera settings',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Colors.red.withOpacity(0.7))),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),

          // --- Inline dropdown at top-left: gear-only or topic-only ---
          Positioned(
            top: 8,
            left: 8,
            child: ButtonTheme(
              alignedDropdown: true,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: EdgeInsets.zero,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isDense: true,
                  iconSize: 18,
                  padding: EdgeInsets.only(right: 0),
                  value: widget.topic,
                  dropdownColor: Colors.grey[850],
                  underline: const SizedBox(),
                  icon: Icon(Icons.arrow_drop_down, color: Colors.white70),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  menuMaxHeight: 300,
                  menuWidth: 300,
                  selectedItemBuilder: widget.hideTopic
                      ? (BuildContext context) {
                          return _sessionTopics.map((t) {
                            return const Icon(Icons.settings,
                                color: Colors.white70);
                          }).toList();
                        }
                      : null,
                  items: _topicLoading || _topicError != null
                      ? []
                      : _sessionTopics.map((t) {
                          return DropdownMenuItem<String>(
                            value: t,
                            child: Text(t,
                                style: const TextStyle(color: Colors.white70)),
                          );
                        }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      Provider.of<SettingsProvider>(context, listen: false)
                          .setCameraImageTopic(value);
                    }
                  },
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  Future<Uint8List?> captureFrame() async {
    try {
      final boundary = _frameKey.currentContext?.findRenderObject();
      if (boundary is RenderRepaintBoundary) {
        final image = await boundary.toImage();
        final byteData = await image.toByteData(format: ImageByteFormat.png);
        return byteData?.buffer.asUint8List();
      }
    } catch (e) {
      print('Frame capture error: $e');
    }
    return null;
  }
}
