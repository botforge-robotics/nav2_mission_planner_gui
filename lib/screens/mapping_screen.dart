import 'package:flutter/material.dart';
import 'package:nav2_mission_planner/providers/settings_provider.dart';
import 'package:nav2_mission_planner/widgets/save_map_dialog.dart';
import 'package:provider/provider.dart';
import '../services/launch_service.dart';
import '../widgets/sensors/joystick_thumb_widget.dart';
import '../widgets/occupancy_grid_viewer.dart';
import '../widgets/sensors/image_viwer.dart';
import '../services/tf_service.dart';

class MappingScreen extends StatefulWidget {
  final Color modeColor;
  const MappingScreen({super.key, required this.modeColor});

  @override
  State<MappingScreen> createState() => _MappingScreenState();
}

class _MappingScreenState extends State<MappingScreen> {
  double _scale = 1.0;
  double _previousScale = 1.0;
  Offset _offset = Offset.zero;
  bool _isMappingStarted = false;
  bool _isMappingActive = false;

  // Add this - don't even create the OccupancyGridViewer until we're ready
  Widget? _mapWidget;

  // Robot position is now handled by TFService

  @override
  void initState() {
    super.initState();
    TFService.instance.initialize(context);
  }

  @override
  void dispose() {
    _mapWidget = null;
    super.dispose();
  }

  // Robot position is now handled by TFService

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background
          Positioned.fill(
            child: Container(color: Colors.black),
          ),

          // Occupancy Grid Map Display - only create it when started
          if (_mapWidget != null)
            Center(child: _mapWidget!)
          else
            Container(
              color: Colors.black87, // 60% - Primary background
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(25),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade800, // 30% - Secondary color
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.map,
                        size: 80,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Mapping Mode',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      'Create a new map of your environment',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 15),
                    ElevatedButton(
                      onPressed: () async {
                        final launchManager =
                            Provider.of<LaunchManager>(context, listen: false);
                        final success =
                            await launchManager.startMapping(context);
                        if (success) {
                          // Create map widget only when we're ready to start
                          setState(() {
                            _isMappingStarted = true;
                            _isMappingActive = true;
                            // Create the widget now that mapping is started
                            _mapWidget = GestureDetector(
                              onScaleStart: (details) {
                                _previousScale = _scale;
                              },
                              onScaleUpdate: (details) {
                                setState(() {
                                  _scale = (_previousScale * details.scale)
                                      .clamp(0.5, 5.0);
                                  if (details.pointerCount == 1) {
                                    final delta = details.focalPoint -
                                        details.localFocalPoint;
                                    _offset = delta;
                                  }
                                });
                              },
                              onScaleEnd: (_) {
                                _previousScale = _scale;
                              },
                              child: Transform.translate(
                                offset: _offset,
                                child: OccupancyGridViewer(
                                  key: const ValueKey('mapping_viewer'),
                                  topic: '/map',
                                  enabled: true,
                                  scale: _scale,
                                  appModeColor: widget.modeColor,
                                  showMarkers: false,
                                  robotPositionStrem:
                                      TFService.instance.robotPositionStream,
                                  onScaleChanged: (newScale) {
                                    setState(() {
                                      _scale = newScale;
                                    });
                                  },
                                ),
                              ),
                            );
                          });
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            widget.modeColor, // 10% - Accent for primary action
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 30, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                            size: 30,
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Start Mapping',
                            style: TextStyle(
                              fontSize: 20,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Joystick Control
          if (_isMappingStarted && _isMappingActive)
            Positioned(
              bottom: 60,
              right: 40,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: JoystickThumbWidget(modeColor: widget.modeColor),
              ),
            ),

          // Status overlay
          if (_isMappingStarted && _isMappingActive)
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Map Active',
                      style: TextStyle(
                        color: widget.modeColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Zoom: ${_scale.toStringAsFixed(1)}x',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                    const Text(
                      'Pinch to zoom • Drag to pan',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_isMappingStarted && _isMappingActive)
            Positioned(
              top: 65,
              right: 16,
              child: Row(
                children: [
                  FloatingActionButton(
                    mini: true,
                    backgroundColor: Colors.red,
                    onPressed: () async {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => AlertDialog(
                          backgroundColor: Colors.transparent,
                          elevation: 0,
                          content: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: Colors.red),
                                const SizedBox(height: 16),
                                const Text(
                                  'Stopping Mapping...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );

                      final launchManager =
                          Provider.of<LaunchManager>(context, listen: false);
                      for (final entry
                          in launchManager.activeLaunches.entries) {
                        try {
                          await launchManager.stopLaunch(context, entry.key);
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error stopping mapping: $e'),
                                backgroundColor: Colors.red.withOpacity(0.9),
                              ),
                            );
                          }
                        }
                      }

                      if (mounted) {
                        Navigator.pop(context); // Dismiss loading
                        setState(() {
                          _isMappingStarted = false;
                          _isMappingActive = false;
                          _mapWidget = null;
                        });
                      }
                    },
                    child: const Icon(Icons.stop, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton(
                    mini: true,
                    backgroundColor: widget.modeColor,
                    onPressed: () async {
                      final result = await showDialog<Map<String, dynamic>>(
                        context: context,
                        builder: (context) => MapSaveDialog(
                          screenSize: MediaQuery.of(context).size,
                          modeColor: widget.modeColor,
                        ),
                      );

                      if (result != null) {
                        final String mapName = result['mapName'];
                        final bool stopMapping = result['stopMapping'];

                        // Show saving overlay
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) => AlertDialog(
                            backgroundColor: Colors.transparent,
                            elevation: 0,
                            content: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(
                                      color: widget.modeColor),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Saving Map...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );

                        final launchManager =
                            Provider.of<LaunchManager>(context, listen: false);
                        final success =
                            await launchManager.saveMap(context, mapName);

                        // Dismiss saving overlay
                        if (mounted) Navigator.pop(context);

                        if (success) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Map saved as $mapName'),
                              backgroundColor: Colors.green.withOpacity(0.9),
                            ),
                          );

                          // Only stop mapping if requested AND save was successful
                          if (stopMapping) {
                            for (final entry
                                in launchManager.activeLaunches.entries) {
                              try {
                                await launchManager.stopLaunch(
                                    context, entry.key);
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error stopping mapping: $e'),
                                    backgroundColor:
                                        Colors.red.withOpacity(0.9),
                                  ),
                                );
                              }
                            }

                            setState(() {
                              _isMappingStarted = false;
                              _isMappingActive = false;
                              _mapWidget = null;
                            });
                          }
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to save map $mapName'),
                              backgroundColor: Colors.red.withOpacity(0.9),
                            ),
                          );
                        }
                      }
                    },
                    child: const Icon(Icons.save, color: Colors.white),
                  ),
                ],
              ),
            ),
          if (_isMappingStarted && _isMappingActive)
            Consumer<SettingsProvider>(
              builder: (context, settings, child) {
                if (!settings.cameraEnabled ||
                    settings.cameraImageTopic.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Positioned(
                  bottom: 20,
                  left: 20,
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width * 0.25,
                    height: MediaQuery.of(context).size.width * 0.25 * (9 / 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: widget.modeColor, width: 2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: ImageViewer(
                          topic: settings.cameraImageTopic,
                          enabled: settings.cameraEnabled,
                          hideTopic: true,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
