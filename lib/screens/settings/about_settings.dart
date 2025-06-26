import 'package:flutter/material.dart';

class AboutSettings extends StatelessWidget {
  final Size screenSize;
  final Color modeColor;

  const AboutSettings(
      {super.key, required this.screenSize, required this.modeColor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: modeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Image.asset(
                'assets/sticker.png',
                width: screenSize.width * 0.22,
                fit: BoxFit.contain,
              ),
            ),

            const SizedBox(height: 15),
            Text(
              'Crafting autonomous solutions with passion and precision.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade400,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 15),
            // Contact details
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.email, size: 16, color: Colors.white70),
                    const SizedBox(width: 6),
                    Text(
                      'reachus@botforge.in',
                      style:
                          const TextStyle(fontSize: 15, color: Colors.white70),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () {},
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.language,
                          size: 16, color: Colors.white70),
                      const SizedBox(width: 6),
                      Text(
                        'https://botforge.in',
                        style: TextStyle(
                            fontSize: 15,
                            color: modeColor,
                            decoration: TextDecoration.underline),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 30),
            Text(
              'Made with ❤️ for ROS2 developers',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
