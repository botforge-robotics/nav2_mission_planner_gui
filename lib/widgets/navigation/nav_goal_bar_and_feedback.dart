import 'package:flutter/material.dart';
import 'package:nav2_msgs/action.dart';
import 'package:nav2_mission_planner/widgets/navigation/nav_bottom_bar.dart';
import 'package:nav2_mission_planner/widgets/navigation/navigation_feedback_widget.dart';

/// Combines the "slide to send goal" confirm bar and the navigation-feedback
/// status overlay (either the live NavigationFeedbackWidget once feedback
/// has arrived, or a "Sending goal…" placeholder before it has). Extracted
/// verbatim from navigation_screen.dart's build() — both blocks are pure
/// render over booleans/objects the screen already computed; the two
/// `showGoalBar`-driven callbacks (`onSlideRight`/`onCancel`) and
/// `onNavigationCancel` are passed straight through unchanged.
class NavGoalBarAndFeedback extends StatelessWidget {
  final bool showGoalBar;
  final VoidCallback onGoalSlideRight;
  final VoidCallback onCancelPendingGoal;

  final bool showNavigationFeedback;
  final NavigateToPoseFeedback? currentFeedback;
  final VoidCallback onNavigationCancel;

  final Color modeColor;

  const NavGoalBarAndFeedback({
    super.key,
    required this.showGoalBar,
    required this.onGoalSlideRight,
    required this.onCancelPendingGoal,
    required this.showNavigationFeedback,
    required this.currentFeedback,
    required this.onNavigationCancel,
    required this.modeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Slide to confirm / cancel goal
        if (showGoalBar)
          NavBottomBar(
            onSlideRight: onGoalSlideRight,
            onCancel: onCancelPendingGoal,
            promptText: 'Slide to send goal',
            visible: showGoalBar,
            color: modeColor,
          ),

        // Navigation status bar (show immediately while waiting for feedback)
        if (showNavigationFeedback)
          currentFeedback != null
              ? NavigationFeedbackWidget(
                  feedback: currentFeedback!,
                  onCancel: onNavigationCancel,
                )
              : Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: 450,
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(modeColor),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Sending goal…',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 14),
                            ),
                          ],
                        ),
                        TextButton(
                          onPressed: onNavigationCancel,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red.shade300,
                          ),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ),
                ),
      ],
    );
  }
}
