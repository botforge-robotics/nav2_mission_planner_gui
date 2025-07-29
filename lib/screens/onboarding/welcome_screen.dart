import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/license_provider.dart';
import '../../providers/branding_provider.dart';
import '../../models/license_model.dart';
import '../license/license_activation_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 800;
    final isMediumScreen = screenSize.width >= 800 && screenSize.width < 1200;

    return Consumer2<LicenseProvider, BrandingProvider>(
      builder: (context, licenseProvider, brandingProvider, child) {
        return Material(
          color: Colors.transparent,
          child: Container(
            padding: EdgeInsets.all(isSmallScreen ? 16.0 : 32.0),
            child: Column(
              children: [
                // Header Section
                _buildHeader(context, isSmallScreen, isMediumScreen),
                SizedBox(height: isSmallScreen ? 12 : 24),

                // Main Content - Dynamic based on license status
                Expanded(
                  child: _buildMainContent(context, licenseProvider,
                      brandingProvider, isSmallScreen),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMainContent(
      BuildContext context,
      LicenseProvider licenseProvider,
      BrandingProvider brandingProvider,
      bool isSmallScreen) {
    switch (licenseProvider.status) {
      case LicenseStatus.welcome:
        // Check if trial is expired to determine layout
        final errorMessage = licenseProvider.errorMessage;
        final isTrialExpired = errorMessage?.contains('Trial expired') == true;

        if (isTrialExpired) {
          // Show only trial section when expired (it has "Activate License" button)
          return _buildTrialSection(context, brandingProvider, isSmallScreen);
        } else if (isSmallScreen) {
          // Stack vertically on small screens
          return Column(
            children: [
              // Top - Free Trial
              Expanded(
                child: _buildTrialSection(
                    context, brandingProvider, isSmallScreen),
              ),
              const SizedBox(height: 16),
              // Bottom - License
              Expanded(
                child: _buildLicenseSection(
                    context, brandingProvider, isSmallScreen),
              ),
            ],
          );
        } else {
          // Side by side on larger screens
          return Row(
            children: [
              // Left Side - Free Trial
              Expanded(
                child: _buildTrialSection(
                    context, brandingProvider, isSmallScreen),
              ),
              // Vertical Separator
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Provider.of<BrandingProvider>(context, listen: false)
                          .themeColor
                          .withValues(alpha: 0.3),
                      Provider.of<BrandingProvider>(context, listen: false)
                          .themeColor
                          .withValues(alpha: 0.3),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.2, 0.8, 1.0],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              // Right Side - License
              Expanded(
                child: _buildLicenseSection(
                    context, brandingProvider, isSmallScreen),
              ),
            ],
          );
        }

      case LicenseStatus.trial:
        return _buildTrialStatusContent(
            context, licenseProvider, isSmallScreen);

      case LicenseStatus.expired:
        return _buildLicenseActivationContent(
            context, licenseProvider, isSmallScreen);

      case LicenseStatus.noInternet:
        return _buildNoInternetContent(context, licenseProvider, isSmallScreen);

      case LicenseStatus.error:
        return _buildErrorContent(context, licenseProvider, isSmallScreen);

      case LicenseStatus.mandatoryCheckRequired:
        return _buildMandatoryVerificationContent(
            context, licenseProvider, isSmallScreen);

      case LicenseStatus.tamperingDetected:
        return _buildTamperingWarningContent(
            context, licenseProvider, isSmallScreen);

      default:
        if (isSmallScreen) {
          return Column(
            children: [
              Expanded(
                  child: _buildTrialSection(
                      context, brandingProvider, isSmallScreen)),
              const SizedBox(height: 16),
              Expanded(
                  child: _buildLicenseSection(
                      context, brandingProvider, isSmallScreen)),
            ],
          );
        } else {
          return Row(
            children: [
              Expanded(
                  child: _buildTrialSection(
                      context, brandingProvider, isSmallScreen)),
              // Vertical Separator
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      brandingProvider.themeColor.withValues(alpha: 0.3),
                      brandingProvider.themeColor.withValues(alpha: 0.3),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.2, 0.8, 1.0],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                  child: _buildLicenseSection(
                      context, brandingProvider, isSmallScreen)),
            ],
          );
        }
    }
  }

  Widget _buildHeader(
      BuildContext context, bool isSmallScreen, bool isMediumScreen) {
    return Consumer2<LicenseProvider, BrandingProvider>(
      builder: (context, licenseProvider, brandingProvider, child) {
        final errorMessage = licenseProvider.errorMessage;
        final isTrialExpired = errorMessage?.contains('Trial expired') == true;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // App Logo/Icon
            Container(
              width: isSmallScreen ? 60 : (isMediumScreen ? 70 : 80),
              height: isSmallScreen ? 60 : (isMediumScreen ? 70 : 80),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    brandingProvider.themeColor,
                    brandingProvider.themeColor.withValues(alpha: 0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(isSmallScreen ? 18 : 24),
                boxShadow: [
                  BoxShadow(
                    color: brandingProvider.themeColor.withValues(alpha: 0.3),
                    blurRadius: isSmallScreen ? 15 : 20,
                    offset: Offset(0, isSmallScreen ? 6 : 8),
                  ),
                ],
              ),
              child: Icon(
                Icons.rocket_launch,
                size: isSmallScreen ? 30 : (isMediumScreen ? 35 : 40),
                color: Colors.white,
              ),
            ),
            SizedBox(width: isSmallScreen ? 16 : 20),

            // Text Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome Title
                  Text(
                    'Welcome to Nav2 Mission Planner',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 24 : (isMediumScreen ? 28 : 32),
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 4 : 6),

                  // Subtitle - Only show when trial is not expired
                  if (!isTrialExpired)
                    Text(
                      'Choose your preferred way to get started',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 14 : 16,
                        color: Colors.white.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTrialSection(BuildContext context,
      BrandingProvider brandingProvider, bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 12 : 15),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Trial Icon
          Container(
            width: isSmallScreen ? 50 : 60,
            height: isSmallScreen ? 50 : 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFF9800),
                  const Color(0xFFFFC107),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(isSmallScreen ? 14 : 16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                  blurRadius: isSmallScreen ? 10 : 12,
                  offset: Offset(0, isSmallScreen ? 3 : 4),
                ),
              ],
            ),
            child: Icon(
              Icons.access_time,
              size: isSmallScreen ? 24 : 28,
              color: Colors.white,
            ),
          ),

          // Trial Title and Status
          Consumer<LicenseProvider>(
            builder: (context, licenseProvider, child) {
              return FutureBuilder<bool>(
                future: licenseProvider.hasActiveTrial(),
                builder: (context, snapshot) {
                  final hasActiveTrial = snapshot.data ?? false;
                  final errorMessage = licenseProvider.errorMessage;
                  final isTrialExpired =
                      errorMessage?.contains('Trial expired') == true;

                  if (isTrialExpired) {
                    return Column(
                      children: [
                        Text(
                          'Trial Expired',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 20 : 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 4 : 6),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: isSmallScreen ? 12 : 16,
                              vertical: isSmallScreen ? 4 : 6),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFFF9800).withValues(alpha: 0.2),
                            borderRadius:
                                BorderRadius.circular(isSmallScreen ? 16 : 20),
                          ),
                          child: Text(
                            'Activate your license now',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 10 : 12,
                              color: const Color(0xFFFF9800),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    );
                  } else if (hasActiveTrial) {
                    return Column(
                      children: [
                        Text(
                          'Trial Active',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 20 : 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 4 : 6),
                        FutureBuilder<int>(
                          future: licenseProvider.getTrialRemainingDays(),
                          builder: (context, daysSnapshot) {
                            final days = daysSnapshot.data ?? 0;
                            return Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: isSmallScreen ? 12 : 16,
                                  vertical: isSmallScreen ? 4 : 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF9800)
                                    .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(
                                    isSmallScreen ? 16 : 20),
                              ),
                              child: Text(
                                '$days days remaining',
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 10 : 12,
                                  color: const Color(0xFFFF9800),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  } else {
                    return Column(
                      children: [
                        Text(
                          'Free Trial',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 20 : 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 4 : 6),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: isSmallScreen ? 12 : 16,
                              vertical: isSmallScreen ? 4 : 6),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFFF9800).withValues(alpha: 0.2),
                            borderRadius:
                                BorderRadius.circular(isSmallScreen ? 16 : 20),
                          ),
                          child: Text(
                            '7 Days • No Credit Card',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 10 : 12,
                              color: const Color(0xFFFF9800),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                },
              );
            },
          ),

          // Trial Button
          Consumer<LicenseProvider>(
            builder: (context, licenseProvider, child) {
              final isLoading =
                  licenseProvider.status == LicenseStatus.checking;

              return FutureBuilder<bool>(
                future: licenseProvider.hasActiveTrial(),
                builder: (context, trialSnapshot) {
                  final hasActiveTrial = trialSnapshot.data ?? false;
                  final errorMessage = licenseProvider.errorMessage;
                  final isTrialExpired =
                      errorMessage?.contains('Trial expired') == true;

                  return SizedBox(
                    width: double.infinity,
                    height: isSmallScreen ? 48 : 56,
                    child: ElevatedButton(
                      onPressed: isLoading
                          ? null
                          : () async {
                              if (isTrialExpired) {
                                // Activate license when trial is expired
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const LicenseActivationScreen(),
                                  ),
                                );
                              } else if (hasActiveTrial) {
                                // Continue with existing trial
                                licenseProvider.allowTrialUsage();
                              } else {
                                // Start new trial
                                try {
                                  final success = await context
                                      .read<LicenseProvider>()
                                      .startTrial();
                                  if (!success) {
                                    final errorMessage = context
                                        .read<LicenseProvider>()
                                        .errorMessage;
                                    // Show error in a dialog instead of SnackBar
                                    if (context.mounted) {
                                      showDialog(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title:
                                              const Text('Trial Start Failed'),
                                          content: Text(errorMessage ??
                                              'Unknown error occurred'),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(context).pop(),
                                              child: const Text(
                                                'OK',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  }
                                } catch (e) {
                                  // Show error in a dialog instead of SnackBar
                                  if (context.mounted) {
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Error'),
                                        content:
                                            Text('Exception: ${e.toString()}'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(context).pop(),
                                            child: const Text('OK'),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brandingProvider.themeColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 8,
                        shadowColor:
                            brandingProvider.themeColor.withValues(alpha: 0.4),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              isTrialExpired
                                  ? 'Activate License'
                                  : hasActiveTrial
                                      ? 'Continue Trial'
                                      : 'Start Free Trial',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLicenseSection(BuildContext context,
      BrandingProvider brandingProvider, bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 12 : 15),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // License Icon
          Container(
            width: isSmallScreen ? 50 : 60,
            height: isSmallScreen ? 50 : 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFF9800),
                  const Color(0xFFFFC107),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(isSmallScreen ? 14 : 16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                  blurRadius: isSmallScreen ? 10 : 12,
                  offset: Offset(0, isSmallScreen ? 3 : 4),
                ),
              ],
            ),
            child: Icon(
              Icons.key,
              size: isSmallScreen ? 24 : 28,
              color: Colors.white,
            ),
          ),
          // License Title
          Text(
            'Full License',
            style: TextStyle(
              fontSize: isSmallScreen ? 20 : 24,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),

          // License Subtitle
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 12 : 16,
                vertical: isSmallScreen ? 4 : 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(isSmallScreen ? 16 : 20),
            ),
            child: Text(
              'Unlimited Access',
              style: TextStyle(
                fontSize: isSmallScreen ? 10 : 12,
                color: const Color(0xFFFF9800),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Activate License Button
          Consumer<LicenseProvider>(
            builder: (context, licenseProvider, child) {
              final isLoading =
                  licenseProvider.status == LicenseStatus.checking;

              return SizedBox(
                width: double.infinity,
                height: isSmallScreen ? 48 : 56,
                child: OutlinedButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) =>
                                  const LicenseActivationScreen(),
                            ),
                          );
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isLoading
                        ? const Color(0xFFFF9800).withValues(alpha: 0.5)
                        : const Color(0xFFFF9800),
                    side: BorderSide(
                        color: isLoading
                            ? const Color(0xFFFF9800).withValues(alpha: 0.5)
                            : const Color(0xFFFF9800),
                        width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    backgroundColor: isLoading
                        ? const Color(0xFFFF9800).withValues(alpha: 0.02)
                        : const Color(0xFFFF9800).withValues(alpha: 0.05),
                  ),
                  child: Text(
                    'Activate License',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isLoading
                          ? const Color(0xFFFF9800).withValues(alpha: 0.5)
                          : const Color(0xFFFF9800),
                    ),
                  ),
                ),
              );
            },
          )
        ],
      ),
    );
  }

  // Trial Status Content
  Widget _buildTrialStatusContent(BuildContext context,
      LicenseProvider licenseProvider, bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 20 : 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFF9800).withValues(alpha: 0.1),
            const Color(0xFFFFC107).withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(isSmallScreen ? 16 : 24),
        border: Border.all(
          color: const Color(0xFFFF9800).withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: isSmallScreen ? 15 : 20,
            offset: Offset(0, isSmallScreen ? 6 : 8),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Trial Icon
          Container(
            width: isSmallScreen ? 50 : 60,
            height: isSmallScreen ? 50 : 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFF9800),
                  const Color(0xFFFFC107),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                  blurRadius: isSmallScreen ? 8 : 12,
                  offset: Offset(0, isSmallScreen ? 3 : 4),
                ),
              ],
            ),
            child: Icon(
              Icons.access_time,
              size: isSmallScreen ? 24 : 28,
              color: Colors.white,
            ),
          ),

          SizedBox(height: isSmallScreen ? 12 : 16),

          // Trial Status
          Column(
            children: [
              Text(
                'Trial Active',
                style: TextStyle(
                  fontSize: isSmallScreen ? 20 : 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: isSmallScreen ? 6 : 8),
              FutureBuilder<int>(
                future: licenseProvider.getTrialRemainingDays(),
                builder: (context, snapshot) {
                  final days = snapshot.data ?? 0;
                  return Text(
                    '$days days remaining',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : 16,
                      color: const Color(0xFFFF9800),
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
            ],
          ),

          SizedBox(height: isSmallScreen ? 16 : 24),

          // Continue Trial Button
          SizedBox(
            width: double.infinity,
            height: isSmallScreen ? 48 : 56,
            child: ElevatedButton(
              onPressed: () {
                // Continue with trial
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
                ),
                elevation: 8,
                shadowColor: const Color(0xFFFF9800).withValues(alpha: 0.4),
              ),
              child: Text(
                'Continue Trial',
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // License Activation Content
  Widget _buildLicenseActivationContent(BuildContext context,
      LicenseProvider licenseProvider, bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 20 : 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFF9800).withValues(alpha: 0.1),
            const Color(0xFFFFC107).withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(isSmallScreen ? 16 : 24),
        border: Border.all(
          color: const Color(0xFFFF9800).withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: isSmallScreen ? 15 : 20,
            offset: Offset(0, isSmallScreen ? 6 : 8),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // License Icon
          Container(
            width: isSmallScreen ? 60 : 80,
            height: isSmallScreen ? 60 : 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFF9800),
                  const Color(0xFFFFC107),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(isSmallScreen ? 16 : 20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                  blurRadius: isSmallScreen ? 12 : 16,
                  offset: Offset(0, isSmallScreen ? 4 : 6),
                ),
              ],
            ),
            child: Icon(
              Icons.key_off,
              size: isSmallScreen ? 32 : 40,
              color: Colors.white,
            ),
          ),

          SizedBox(height: isSmallScreen ? 16 : 24),

          // Title
          Text(
            'License Expired',
            style: TextStyle(
              fontSize: isSmallScreen ? 24 : 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),

          SizedBox(height: isSmallScreen ? 8 : 12),

          // Subtitle
          Text(
            'Your license has expired or is invalid.\nPlease activate a new license to continue.',
            style: TextStyle(
              fontSize: isSmallScreen ? 14 : 16,
              color: Colors.white.withValues(alpha: 0.8),
            ),
            textAlign: TextAlign.center,
          ),

          SizedBox(height: isSmallScreen ? 24 : 32),

          // Activate License Button
          SizedBox(
            width: double.infinity,
            height: isSmallScreen ? 48 : 56,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const LicenseActivationScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
                ),
                elevation: 8,
                shadowColor: const Color(0xFFFF9800).withValues(alpha: 0.4),
              ),
              child: Text(
                'Activate License',
                style: TextStyle(
                  fontSize: isSmallScreen ? 16 : 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // No Internet Content
  Widget _buildNoInternetContent(BuildContext context,
      LicenseProvider licenseProvider, bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 20 : 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // No Internet Icon
          Container(
            width: isSmallScreen ? 50 : 60,
            height: isSmallScreen ? 50 : 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFF9800),
                  const Color(0xFFFFC107),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                  blurRadius: isSmallScreen ? 8 : 12,
                  offset: Offset(0, isSmallScreen ? 3 : 4),
                ),
              ],
            ),
            child: Icon(
              Icons.wifi_off,
              size: isSmallScreen ? 24 : 28,
              color: Colors.white,
            ),
          ),

          // Title
          Text(
            'Internet Required',
            style: TextStyle(
              fontSize: isSmallScreen ? 20 : 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),

          // Message
          Text(
            'Please check your internet connection and try again.',
            style: TextStyle(
              fontSize: isSmallScreen ? 14 : 16,
              color: Colors.white.withValues(alpha: 0.8),
            ),
            textAlign: TextAlign.center,
          ),

          // Retry Button
          SizedBox(
            width: double.infinity,
            height: isSmallScreen ? 48 : 56,
            child: ElevatedButton(
              onPressed: () {
                licenseProvider.checkLicense();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
                ),
              ),
              child: Text(
                'Retry',
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Error Content
  Widget _buildErrorContent(BuildContext context,
      LicenseProvider licenseProvider, bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 20 : 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFF9800).withValues(alpha: 0.1),
            const Color(0xFFFFC107).withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(isSmallScreen ? 16 : 24),
        border: Border.all(
          color: const Color(0xFFFF9800).withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: isSmallScreen ? 15 : 20,
            offset: Offset(0, isSmallScreen ? 6 : 8),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Error Icon
          Container(
            width: isSmallScreen ? 50 : 60,
            height: isSmallScreen ? 50 : 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFF9800),
                  const Color(0xFFFFC107),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                  blurRadius: isSmallScreen ? 8 : 12,
                  offset: Offset(0, isSmallScreen ? 3 : 4),
                ),
              ],
            ),
            child: Icon(
              Icons.error_outline,
              size: isSmallScreen ? 24 : 28,
              color: Colors.white,
            ),
          ),

          SizedBox(height: isSmallScreen ? 12 : 16),

          // Title
          Text(
            'Error',
            style: TextStyle(
              fontSize: isSmallScreen ? 20 : 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),

          SizedBox(height: isSmallScreen ? 8 : 12),

          // Error Message
          Text(
            licenseProvider.errorMessage ?? 'An error occurred',
            style: TextStyle(
              fontSize: isSmallScreen ? 14 : 16,
              color: Colors.white.withValues(alpha: 0.8),
            ),
            textAlign: TextAlign.center,
          ),

          SizedBox(height: isSmallScreen ? 16 : 24),

          // Retry Button
          SizedBox(
            width: double.infinity,
            height: isSmallScreen ? 48 : 56,
            child: ElevatedButton(
              onPressed: () {
                licenseProvider.checkLicense();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
                ),
              ),
              child: Text(
                'Retry',
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Mandatory Verification Content
  Widget _buildMandatoryVerificationContent(BuildContext context,
      LicenseProvider licenseProvider, bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 20 : 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFF9800).withValues(alpha: 0.1),
            const Color(0xFFFFC107).withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(isSmallScreen ? 16 : 24),
        border: Border.all(
          color: const Color(0xFFFF9800).withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: isSmallScreen ? 15 : 20,
            offset: Offset(0, isSmallScreen ? 6 : 8),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Icon
          Container(
            width: isSmallScreen ? 50 : 60,
            height: isSmallScreen ? 50 : 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFF9800),
                  const Color(0xFFFFC107),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.3),
                  blurRadius: isSmallScreen ? 8 : 12,
                  offset: Offset(0, isSmallScreen ? 3 : 4),
                ),
              ],
            ),
            child: Icon(
              Icons.cloud_sync,
              size: isSmallScreen ? 24 : 28,
              color: Colors.white,
            ),
          ),

          SizedBox(height: isSmallScreen ? 12 : 16),

          // Title
          Text(
            'Online Verification Required',
            style: TextStyle(
              fontSize: isSmallScreen ? 20 : 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),

          SizedBox(height: isSmallScreen ? 8 : 12),

          // Description
          Text(
            'Your app requires a mandatory online verification every 30 days to ensure security and prevent unauthorized use.',
            style: TextStyle(
              fontSize: isSmallScreen ? 14 : 16,
              color: Colors.white.withValues(alpha: 0.8),
            ),
            textAlign: TextAlign.center,
          ),

          SizedBox(height: isSmallScreen ? 12 : 16),

          // Information box
          Container(
            padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(isSmallScreen ? 8 : 12),
              border: Border.all(
                color: const Color(0xFFFF9800).withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Why is this required?',
                  style: TextStyle(
                    color: const Color(0xFFFF9800),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _buildInfoItem('• Ensures license/trial validity'),
                _buildInfoItem('• Prevents unauthorized usage'),
                _buildInfoItem('• Updates security measures'),
                _buildInfoItem('• Syncs with server data'),
              ],
            ),
          ),

          // Retry Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () async {
                await licenseProvider.checkLicense();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Verify Now',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Tampering Warning Content
  Widget _buildTamperingWarningContent(BuildContext context,
      LicenseProvider licenseProvider, bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 20 : 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFFF9800).withValues(alpha: 0.1),
            const Color(0xFFFFC107).withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(isSmallScreen ? 16 : 24),
        border: Border.all(
          color: const Color(0xFFFF9800).withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: isSmallScreen ? 15 : 20,
            offset: Offset(0, isSmallScreen ? 6 : 8),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Warning Icon
          Container(
            width: isSmallScreen ? 50 : 60,
            height: isSmallScreen ? 50 : 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.red,
                  Colors.orange,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(isSmallScreen ? 12 : 16),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withValues(alpha: 0.3),
                  blurRadius: isSmallScreen ? 8 : 12,
                  offset: Offset(0, isSmallScreen ? 3 : 4),
                ),
              ],
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              size: isSmallScreen ? 24 : 28,
              color: Colors.white,
            ),
          ),

          SizedBox(height: isSmallScreen ? 12 : 16),

          // Title
          Text(
            'Time Tampering Detected',
            style: TextStyle(
              fontSize: isSmallScreen ? 20 : 24,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
            textAlign: TextAlign.center,
          ),

          SizedBox(height: isSmallScreen ? 8 : 12),

          // Description
          Text(
            'We detected that the device time has been modified. This is not allowed and may indicate an attempt to bypass the trial or license system.',
            style: TextStyle(
              fontSize: isSmallScreen ? 14 : 16,
              color: Colors.white.withValues(alpha: 0.8),
            ),
            textAlign: TextAlign.center,
          ),

          SizedBox(height: isSmallScreen ? 12 : 16),

          // Possible causes
          Container(
            padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(isSmallScreen ? 8 : 12),
              border: Border.all(
                color: Colors.orange.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Possible Causes:',
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _buildInfoItem('• Device time was manually changed'),
                _buildInfoItem('• Device was restored from backup'),
                _buildInfoItem('• System clock was modified'),
                _buildInfoItem('• Device was reset to factory settings'),
              ],
            ),
          ),

          // Retry Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () async {
                await licenseProvider.checkLicense();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Retry',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper method for info items
  Widget _buildInfoItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          color: Colors.white.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}
