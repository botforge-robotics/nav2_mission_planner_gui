import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/license_provider.dart';

class TopStatusTrialIndicator extends StatelessWidget {
  const TopStatusTrialIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LicenseProvider>(
      builder: (context, licenseProvider, child) {
        // Check if user has active trial (regardless of current status)
        return FutureBuilder<bool>(
          future: licenseProvider.hasActiveTrial(),
          builder: (context, trialSnapshot) {
            if (!trialSnapshot.hasData || !trialSnapshot.data!) {
              return const SizedBox.shrink();
            }

            // Get remaining days
            return FutureBuilder<int>(
              future: licenseProvider.getTrialRemainingDays(),
              builder: (context, daysSnapshot) {
                if (!daysSnapshot.hasData || daysSnapshot.data! <= 0) {
                  return const SizedBox.shrink();
                }

                final remainingDays = daysSnapshot.data!;

                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    border: Border.all(
                      color: Colors.red,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.access_time,
                        color: Colors.red,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Trial: $remainingDays days',
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
