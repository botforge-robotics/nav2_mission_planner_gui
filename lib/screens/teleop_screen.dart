import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/live_telemetry_provider.dart';
import '../widgets/sensors/image_viwer.dart';
import '../widgets/sensors/joystick_thumb_widget.dart';
import '../widgets/camera_snap_button.dart';

class TeleopScreen extends StatelessWidget {
  final Color modeColor;
  const TeleopScreen({super.key, required this.modeColor});

  @override
  Widget build(BuildContext context) {
    final GlobalKey<ImageViewerState> imageViewerKey = GlobalKey();

    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return Stack(
          children: [
            // Full screen image viewer
            if (settings.cameraEnabled && settings.cameraImageTopic.isNotEmpty)
              Positioned.fill(
                child: Container(
                  color: Colors.black,
                  child: ImageViewer(
                    key: imageViewerKey,
                    topic: settings.cameraImageTopic,
                    enabled: settings.cameraEnabled,
                  ),
                ),
              ),

            // Show message when camera is disabled or no topic selected
            if (!settings.cameraEnabled || settings.cameraImageTopic.isEmpty)
              Container(
                color: Colors.black87,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Icon and title
                      Container(
                        padding: const EdgeInsets.all(25),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade800,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.videocam_off,
                          size: 80,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Teleop Mode',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 15),
                      Text(
                        'Camera feed is disabled',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),

            // Joystick
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
                child: JoystickThumbWidget(
                  modeColor: modeColor,
                  // Shared with screens that don't own a joystick
                  // (Dashboard, Robot Status) so they can read "is teleop
                  // active" from one place — see LiveTelemetryProvider.
                  onCommand: (linear, angular) {
                    Provider.of<LiveTelemetryProvider>(context, listen: false)
                        .reportTeleopCommand(linear, angular);
                  },
                ),
              ),
            ),

            CameraSnapButton(
              modeColor: modeColor,
              isCameraActive: settings.cameraEnabled &&
                  settings.cameraImageTopic.isNotEmpty,
              getCurrentFrame: () async =>
                  imageViewerKey.currentState?.captureFrame(),
            ),
          ],
        );
      },
    );
  }
}
