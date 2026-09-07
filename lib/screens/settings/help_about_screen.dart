import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import 'software_update_screen.dart';

class HelpAboutScreen extends StatefulWidget {
  const HelpAboutScreen({super.key});

  @override
  State<HelpAboutScreen> createState() => _HelpAboutScreenState();
}

class _HelpAboutScreenState extends State<HelpAboutScreen> {
  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _info = info);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & About')),
      body: SafeArea(
        child: CenteredFormColumn(
          maxWidth: 480,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline_rounded,
                      color: AppColors.primary),
                  title: const Text('App version'),
                  subtitle: Text(_info != null
                      ? '${_info!.version} (${_info!.buildNumber})'
                      : '—'),
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.system_update_alt_rounded, size: 16),
                    label: const Text('Updates'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SoftwareUpdateScreen(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.menu_book_rounded,
                      color: AppColors.primary),
                  title: const Text('SDK documentation'),
                  subtitle:
                      const Text('botforge-robotics.github.io/navpromini_sdk'),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                  onTap: () => launchUrl(
                    Uri.parse(
                        'https://botforge-robotics.github.io/navpromini_sdk/'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Card(
                child: ListTile(
                  leading:
                      Icon(Icons.smart_toy_rounded, color: AppColors.primary),
                  title: Text('Model'),
                  subtitle: Text('NavPro Mini — BOTFORGE Robotics'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
