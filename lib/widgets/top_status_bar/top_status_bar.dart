import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../providers/connection_provider.dart';
import '../../providers/branding_provider.dart';
import '../../services/launch_service.dart';
import 'top_status_center_title.dart';
import 'top_status_network_info.dart';
import 'top_status_connection_button.dart';
import 'top_status_battery.dart';
import 'top_status_temperature.dart';

/// Connection/telemetry/branding strip across the top of the app shell.
///
/// Mode selection used to live here too (via `TopStatusModeSelector`, a
/// dropdown menu) — that responsibility has moved to the persistent
/// `AppNavRail` alongside the content, so this bar is now presentation-only:
/// connection status, battery/temperature/network readouts, and the
/// branding chip. `statusText`/`statusColor`/`icon`/mode-change plumbing
/// (and the session-active guard that used to intercept mode changes here)
/// moved with the mode selector — the guard now lives in `HomeScreen`,
/// wrapping `AppNavRail`'s destination taps instead.
class TopStatusBar extends StatelessWidget {
  final double height;

  const TopStatusBar({
    super.key,
    this.height = 50.0,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionProvider>(
      builder: (context, connection, child) {
        final connectionStatusColor =
            connection.isConnected ? Colors.greenAccent : Colors.red;

        return Container(
          height: height,
          color: AppTheme.toolbarColor,
          child: Stack(
            children: [
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 10, color: connectionStatusColor),
                    const SizedBox(width: 8),
                    Text(
                      connection.isConnected ? 'Connected' : 'Disconnected',
                      style: TextStyle(
                        color: connectionStatusColor,
                        fontSize: height * 0.28,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const TopStatusCenterTitle(),
              Positioned(
                right: -9,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (connection.isConnected)
                      TopStatusBattery(
                        height: height,
                        accentColor: connectionStatusColor,
                      ),
                    // Order: battery % -> battery temp -> CPU temp -> network.
                    // The two battery readings sit together so they read as
                    // one group, with CPU temperature immediately after them
                    // rather than separated by the network block.
                    if (connection.isConnected)
                      TopStatusTemperature(
                        height: height,
                        accentColor: connectionStatusColor,
                        kind: TempKind.battery,
                      ),
                    if (connection.isConnected)
                      TopStatusTemperature(
                        height: height,
                        accentColor: connectionStatusColor,
                        kind: TempKind.cpu,
                      ),
                    if (connection.isConnected)
                      TopStatusNetworkInfo(
                        height: height,
                        connectionStatusColor: connectionStatusColor,
                      ),
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
                                branding.themeColor.withValues(alpha: 0.9),
                                branding.themeColor.withValues(alpha: 0.0),
                              ],
                            ),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(height * 0.25),
                              bottomLeft: Radius.circular(height * 0.25),
                            ),
                          ),
                          child: branding.createFaviconWidget(
                            height: height * 0.5,
                            fit: BoxFit.contain,
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
