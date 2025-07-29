import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/branding_provider.dart';

class AboutSettings extends StatelessWidget {
  final Size screenSize;
  final Color modeColor;

  const AboutSettings(
      {super.key, required this.screenSize, required this.modeColor});

  @override
  Widget build(BuildContext context) {
    return Consumer<BrandingProvider>(
      builder: (context, branding, child) {
        return Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Dynamic Logo
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: branding.themeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Image.asset(
                    branding.logoUrl,
                    width: screenSize.width * 0.22,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      // Fallback to default logo
                      return Image.asset(
                        'assets/sticker.png',
                        width: screenSize.width * 0.22,
                        fit: BoxFit.contain,
                      );
                    },
                  ),
                ),

                const SizedBox(height: 15),
                // Dynamic Tagline
                Text(
                  branding.tagLine,
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
                        const Icon(Icons.email,
                            size: 16, color: Colors.white70),
                        const SizedBox(width: 6),
                        Text(
                          branding.supportEmail,
                          style: const TextStyle(
                              fontSize: 15, color: Colors.white70),
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
                            branding.website,
                            style: TextStyle(
                                fontSize: 15,
                                color: branding.themeColor,
                                decoration: TextDecoration.underline),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 30),
                // Dynamic Footer Credits
                Text(
                  branding.footerCredits,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
