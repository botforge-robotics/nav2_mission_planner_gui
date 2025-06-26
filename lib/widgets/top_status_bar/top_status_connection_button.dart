import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/connection_provider.dart';
import '../../services/launch_service.dart';

class TopStatusConnectionButton extends StatefulWidget {
  final double height;
  final Color connectionStatusColor;
  final bool isDisabled;

  const TopStatusConnectionButton({
    super.key,
    required this.height,
    required this.connectionStatusColor,
    this.isDisabled = false,
  });

  @override
  _TopStatusConnectionButtonState createState() =>
      _TopStatusConnectionButtonState();
}

class _TopStatusConnectionButtonState extends State<TopStatusConnectionButton> {
  StreamSubscription? _connectionSub;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    final connectionProvider =
        Provider.of<ConnectionProvider>(context, listen: false);
    _connectionSub = connectionProvider.connectionStream.listen((state) {
      if (!mounted || _disposed) return;
      // Handle connection state changes here
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _connectionSub?.cancel();
    super.dispose();
  }

  // Standardized SnackBar colors
  void _showInfoSnackBar(BuildContext context, String message) {
    if (!mounted || _disposed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    if (!mounted || _disposed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showDisconnectDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.link_off, color: Colors.red),
            ),
            const SizedBox(width: 12),
            const Text('Disconnect from Robot'),
          ],
        ),
        content: const Text(
          'Are you sure you want to disconnect from the current robot?',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.link_off),
            label: const Text('Disconnect'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              try {
                final launchManager =
                    Provider.of<LaunchManager>(context, listen: false);

                // Stop all active launches
                if (launchManager.activeLaunches.isNotEmpty) {
                  _showInfoSnackBar(context, 'Stopping active processes...');

                  // Make a copy of the active launches to avoid modification during iteration
                  final activeIds = launchManager.activeLaunches.keys.toList();

                  // Stop each launch
                  for (final id in activeIds) {
                    await launchManager.stopLaunch(context, id);
                  }
                }

                // Disconnect from ROS2
                await Provider.of<ConnectionProvider>(context, listen: false)
                    .disconnect();

                Navigator.pop(context); // Close dialog

                _showInfoSnackBar(context, 'Disconnected successfully');
              } catch (e) {
                _showErrorSnackBar(
                    context, 'Failed to disconnect: ${e.toString()}');
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionProvider>(
      builder: (context, connection, _) {
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(right: 5),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return ScaleTransition(scale: animation, child: child);
              },
              child: IconButton(
                key: ValueKey<bool>(connection.isConnected),
                icon: Icon(
                  connection.isConnected ? Icons.link : Icons.link_off,
                  color: connection.isConnected ? Colors.green : Colors.red,
                  size: 28,
                ),
                onPressed: () {
                  if (connection.isConnected) {
                    _showDisconnectDialog(context);
                  }
                },
                tooltip: connection.isConnected
                    ? 'Connected to ${connection.ip}:${connection.port}'
                    : 'Connection Settings',
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(8),
                  backgroundColor: connection.isConnected
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.red.withValues(alpha: 0.15),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
