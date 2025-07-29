import 'package:flutter/material.dart';
import 'package:nav2_mission_planner/services/launch_service.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/connection_provider.dart';
import '../../constants/modes.dart';
import '../../providers/branding_provider.dart';
import 'top_status_mode_selector.dart';
import 'top_status_center_title.dart';
import 'top_status_network_info.dart';
import 'top_status_connection_button.dart';
import 'top_status_trial_indicator.dart';

class TopStatusBar extends StatelessWidget {
  final String statusText;
  final Color statusColor;
  final double height;
  final IconData? icon;
  final AppModes currentMode;
  final Function(AppModes) onModeChanged;

  const TopStatusBar({
    super.key,
    required this.statusText,
    required this.statusColor,
    this.height = 50.0,
    this.icon,
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionProvider>(
      builder: (context, connection, child) {
        final connectionStatusColor =
            connection.isConnected ? statusColor : Colors.red;
        final displayStatusText =
            connection.isConnected ? statusText : 'Disconnected';

        return Container(
          height: height,
          color: AppTheme.toolbarColor,
          child: Stack(
            children: [
              TopStatusModeSelector(
                height: height,
                connectionStatusColor: connectionStatusColor,
                displayStatusText: displayStatusText,
                currentMode: currentMode,
                onModeChanged: (newMode) async {
                  final launchManager =
                      Provider.of<LaunchManager>(context, listen: false);
                  final activeSession = launchManager.activeSession;

                  // Allow only specific mode transitions when sessions are active
                  if (activeSession == SessionType.mapping &&
                      newMode != AppModes.settings &&
                      newMode != AppModes.mapping) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Stop mapping before changing modes'),
                        backgroundColor: Colors.red.withOpacity(0.9),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    return;
                  }

                  // Handle active navigation session
                  if (activeSession == SessionType.navigation &&
                      newMode != AppModes.settings &&
                      newMode != AppModes.navigation) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Stop navigation before changing modes'),
                        backgroundColor: Colors.red.withOpacity(0.9),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    return;
                  }

                  if (newMode == AppModes.settings) {
                    onModeChanged(newMode);
                    return;
                  }

                  // Handle stopping active navigation or mapping sessions
                  if ((currentMode == AppModes.mapping ||
                          currentMode == AppModes.navigation) &&
                      newMode != currentMode) {
                    final launchManager =
                        Provider.of<LaunchManager>(context, listen: false);
                    if (launchManager.activeLaunches.isNotEmpty) {
                      final shouldStop = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Active Session'),
                          content: Text(
                              'You have an active ${currentMode.name} session. Stop it before changing modes?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Keep Running'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.withOpacity(0.9),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Stop Session'),
                            ),
                          ],
                        ),
                      );

                      if (shouldStop ?? false) {
                        for (final entry
                            in launchManager.activeLaunches.entries) {
                          try {
                            await launchManager.stopLaunch(context, entry.key);
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Failed to stop session: ${e.toString()}'),
                                backgroundColor: Colors.red.withOpacity(0.9),
                              ),
                            );
                          }
                        }
                      } else {
                        return; // Abort mode change
                      }
                    }
                  }

                  // Proceed with mode change
                  onModeChanged(newMode);
                },
              ),
              const TopStatusCenterTitle(),
              Positioned(
                right: -9,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (connection.isConnected)
                      TopStatusNetworkInfo(
                        height: height,
                        connectionStatusColor: connectionStatusColor,
                      ),
                    const TopStatusTrialIndicator(),
                    TopStatusConnectionButton(
                      height: height,
                      connectionStatusColor: connectionStatusColor,
                      isDisabled:
                          Provider.of<LaunchManager>(context, listen: false)
                              .activeLaunches
                              .isNotEmpty,
                    ),
                    Consumer<BrandingProvider>(
                      builder: (context, branding, child) {
                        return Container(
                          padding: EdgeInsets.all(height * 0.2),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomRight,
                              end: Alignment.topLeft,
                              colors: [
                                branding.themeColor.withOpacity(0.9),
                                branding.themeColor.withOpacity(0.0),
                              ],
                            ),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(height * 0.25),
                              bottomLeft: Radius.circular(height * 0.25),
                            ),
                          ),
                          child: Image.asset(
                            branding.faviconUrl,
                            height: height * 0.5,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              // Fallback to default favicon
                              return Image.asset(
                                'assets/favicon_light.png',
                                height: height * 0.5,
                                fit: BoxFit.contain,
                              );
                            },
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 10),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
