import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/license_provider.dart';
import '../../models/license_model.dart';

class TopStatusTrialIndicator extends StatelessWidget {
  const TopStatusTrialIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LicenseProvider>(
      builder: (context, licenseProvider, child) {
        // Don't show trial indicator if license verification is still in progress
        if (licenseProvider.status == LicenseStatus.checking) {
          return const SizedBox.shrink();
        }

        // Don't show trial indicator if trial has expired
        if (licenseProvider.status == LicenseStatus.expired ||
            licenseProvider.isTrialExpired()) {
          return const SizedBox.shrink();
        }

        // Show trial indicator if status is trial or if there's an active trial
        if (licenseProvider.status == LicenseStatus.trial ||
            licenseProvider.isTrialActive()) {
          // Get remaining days directly
          return FutureBuilder<int>(
            future: licenseProvider.getTrialRemainingDays(),
            builder: (context, daysSnapshot) {
              if (!daysSnapshot.hasData || daysSnapshot.data! <= 0) {
                return const SizedBox.shrink();
              }

              final remainingDays = daysSnapshot.data!;

              return Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
        }

        // Don't show trial indicator if there's a valid license
        if (licenseProvider.isLicenseValid()) {
          return const SizedBox.shrink();
        }

        // Check if user has active trial (fallback for other statuses)
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
