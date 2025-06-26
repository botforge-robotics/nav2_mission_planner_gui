import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraSnapButton extends StatelessWidget {
  final Color modeColor;
  final bool isCameraActive;
  final Future<Uint8List?> Function() getCurrentFrame;

  const CameraSnapButton({
    super.key,
    required this.modeColor,
    required this.isCameraActive,
    required this.getCurrentFrame,
  });

  Future<void> _saveImage(BuildContext context) async {
    if (await Permission.storage.request().isGranted) {
      final frame = await getCurrentFrame();
      if (frame != null) {
        await ImageGallerySaver.saveImage(frame, quality: 90);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Image saved to gallery'),
            backgroundColor: Colors.green.withOpacity(0.9),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Visibility(
      visible: isCameraActive,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  modeColor.withOpacity(0.15),
                  Colors.transparent,
                ],
                stops: [0.1, 0.8],
              ),
              border: Border.all(
                color: modeColor.withOpacity(0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(
                Icons.camera_alt,
                size: 30,
                color: modeColor.withOpacity(0.9),
                shadows: [
                  Shadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 4,
                    offset: Offset(1, 1),
                  ),
                ],
              ),
              onPressed: () => _saveImage(context),
              splashColor: modeColor.withOpacity(0.2),
              highlightColor: modeColor.withOpacity(0.1),
              tooltip: 'Take photo',
            ),
          ),
        ),
      ),
    );
  }
}
