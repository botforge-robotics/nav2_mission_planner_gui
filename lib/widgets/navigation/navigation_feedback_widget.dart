import 'package:flutter/material.dart';
import 'package:builtin_interfaces/msg.dart';
import 'package:nav2_msgs/action.dart';
import 'package:provider/provider.dart';
import '../../providers/branding_provider.dart';

class NavigationFeedbackWidget extends StatelessWidget {
  final NavigateToPoseFeedback feedback;
  final VoidCallback onCancel;

  const NavigationFeedbackWidget({
    super.key,
    required this.feedback,
    required this.onCancel,
  });

  String _formatDuration(Duration time) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    int totalSeconds = time.sec;
    int minutes = totalSeconds ~/ 60;
    int seconds = totalSeconds % 60;
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: 450,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.navigation,
                  color: Provider.of<BrandingProvider>(context, listen: false)
                      .themeColor,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Row(
                  children: [
                    _buildInfo(
                      label: 'Elapsed Time',
                      value: _formatDuration(feedback.navigation_time),
                    ),
                    const SizedBox(width: 16),
                    _buildInfo(
                      label: 'ETR',
                      value: _formatDuration(feedback.estimated_time_remaining),
                    ),
                    const SizedBox(width: 16),
                    _buildInfo(
                      label: 'Distance To GO',
                      value:
                          '${feedback.distance_remaining.toStringAsFixed(1)}m',
                    ),
                  ],
                ),
              ],
            ),
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade300,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfo({required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 11,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
