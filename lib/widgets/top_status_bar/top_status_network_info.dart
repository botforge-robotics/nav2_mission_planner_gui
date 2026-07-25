import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/connection_provider.dart';

class TopStatusNetworkInfo extends StatelessWidget {
  final double height;
  final Color connectionStatusColor;

  const TopStatusNetworkInfo({
    super.key,
    required this.height,
    required this.connectionStatusColor,
  });

  @override
  Widget build(BuildContext context) {
    final connection = Provider.of<ConnectionProvider>(context);

    return Container(
      height: height * 0.7, // Match trial badge height
      padding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 4), // Reduced vertical padding
      margin: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center, // Center align content
        crossAxisAlignment:
            CrossAxisAlignment.center, // Center align vertically
        children: [
          Icon(Icons.language,
              color: connectionStatusColor, size: 12), // Reduced icon size
          const SizedBox(width: 4), // Reduced spacing
          Text(
            connection.ip.isNotEmpty
                ? 'Robot IP: ${connection.ip}'
                : 'Not Connected',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
