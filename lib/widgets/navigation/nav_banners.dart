import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// "Long press on map to add location" pill shown while mission mode is
/// active. Extracted verbatim from navigation_screen.dart's build() — pure
/// render, no state.
class MissionInfoBanner extends StatelessWidget {
  final Color modeColor;

  const MissionInfoBanner({super.key, required this.modeColor});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 20,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: modeColor.withOpacity(0.9),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Text(
                'Long press on map to add location',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placement-instruction pill shown while setting the initial pose, aiming a
/// goal, or dropping a bookmark. Extracted verbatim from
/// navigation_screen.dart's build() — pure render, no state; the caller
/// decides *whether* to show it (the original `if` condition combining
/// showInitialPoseBanner/goalMode/isGoalActive/showGoalBar/bookmarksMode
/// stays at the call site, unchanged).
class PlacementHintBanner extends StatelessWidget {
  final Color modeColor;
  final bool missionInfoBannerShowing;
  final bool showInitialPoseBanner;
  final bool goalMode;
  final bool poseEstimationMode;

  const PlacementHintBanner({
    super.key,
    required this.modeColor,
    required this.missionInfoBannerShowing,
    required this.showInitialPoseBanner,
    required this.goalMode,
    required this.poseEstimationMode,
  });

  @override
  Widget build(BuildContext context) {
    final bool isPoseEstimation = poseEstimationMode || showInitialPoseBanner;
    return Positioned(
      top: missionInfoBannerShowing ? 80 : 20,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isPoseEstimation
                ? Colors.orange.withOpacity(0.9)
                : modeColor.withOpacity(0.9),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isPoseEstimation ? Icons.my_location : Icons.navigation,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                goalMode
                    ? (kIsWeb
                        ? 'Set goal — drag to aim · release · then slide to send'
                        : 'Set goal — long-press drag to aim · release · slide to send')
                    : isPoseEstimation
                        ? (kIsWeb
                            ? 'Set initial pose — drag to aim, release to set'
                            : 'Set initial pose — long-press drag to aim, release to set')
                        : (kIsWeb
                            ? 'Drag to place bookmark · release to save'
                            : 'Long-press drag to place bookmark · release to save'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
