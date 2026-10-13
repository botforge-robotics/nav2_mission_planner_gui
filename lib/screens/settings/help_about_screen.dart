import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_theme.dart';
import '../../theme/breakpoints.dart';
import '../../widgets/design/fade_in.dart';
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
    final colors = AppColors.of(context);
    final isDesktop = Breakpoints.of(context) == DeviceClass.desktop;

    return Scaffold(
      appBar: AppBar(title: const Text('Help & System About')),
      body: SafeArea(
        child: CenteredFormColumn(
          maxWidth: isDesktop ? 680 : 540,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              // Hero Brand Header
              FadeSlideIn(
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: colors.border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [colors.primary, colors.primaryDark],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.smart_toy_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'NavPro Cockpit',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Enterprise Autonomous Mobile Robot Mission Suite',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          alignment: WrapAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                _info != null ? 'v${_info!.version}' : 'v2.1.4',
                                style: TextStyle(
                                  color: colors.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: colors.surfaceSunken,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: colors.border),
                              ),
                              child: Text(
                                'ROS 2 & Nav2 Native',
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: colors.surfaceSunken,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: colors.border),
                              ),
                              child: Text(
                                'Botforge Core',
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // Software & Updates Card
              FadeSlideIn(
                delay: const Duration(milliseconds: 40),
                child: Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 4),
                        child: Text(
                          'Software & Versions',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: colors.textSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                      ListTile(
                        leading: Icon(Icons.info_outline_rounded, color: colors.primary),
                        title: const Text('Application Build'),
                        subtitle: Text(
                          _info != null
                              ? 'Version ${_info!.version} (Build ${_info!.buildNumber})'
                              : 'Loading build info…',
                        ),
                        trailing: FilledButton.tonalIcon(
                          icon: const Icon(Icons.system_update_alt_rounded, size: 16),
                          label: const Text('Check Updates'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SoftwareUpdateScreen(),
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.hardware_rounded, color: colors.primary),
                        title: const Text('Target Hardware Platform'),
                        subtitle: const Text('Botforge NavPro Mini AMR (Differential Drive)'),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              // Documentation & Resources Card
              FadeSlideIn(
                delay: const Duration(milliseconds: 80),
                child: Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 4),
                        child: Text(
                          'Developer Resources & Documentation',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: colors.textSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                      ListTile(
                        leading: Icon(Icons.menu_book_rounded, color: colors.primary),
                        title: const Text('NavPro SDK API Documentation'),
                        subtitle: const Text('REST endpoints, WebSockets, Python & ROS2 bindings'),
                        trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                        onTap: () => launchUrl(
                          Uri.parse('https://botforge-robotics.github.io/navpromini_sdk/'),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.code_rounded, color: colors.primary),
                        title: const Text('Botforge Robotics Open Source'),
                        subtitle: const Text('github.com/botforge-robotics'),
                        trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                        onTap: () => launchUrl(
                          Uri.parse('https://github.com/botforge-robotics'),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              Center(
                child: Text(
                  '© BOTFORGE Robotics Inc. Licensed under Apache 2.0',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textSecondary.withValues(alpha: 0.8),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}
