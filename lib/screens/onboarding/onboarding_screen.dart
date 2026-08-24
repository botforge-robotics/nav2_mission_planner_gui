import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../connection_screen.dart';

/// One-time first-run carousel — the redesign reference's generic "welcome
/// to the app" 3-slide onboarding, adapted per the redesign plan (§6) to
/// this product's actual first-run need: explaining IP-based rosbridge
/// pairing, not generic marketing copy, since there's no login/account
/// step for a slide to lead into.
///
/// Shown at most once per install, gated by a local `hasSeenOnboarding`
/// flag — see [OnboardingGate].
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const String seenPrefsKey = 'hasSeenOnboarding';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Slide {
  final IconData icon;
  final String title;
  final String body;
  const _Slide(
      {required this.icon, required this.title, required this.body});
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _slides = [
    _Slide(
      icon: Icons.smart_toy_outlined,
      title: 'This app talks directly to your robot',
      body:
          'No cloud, no account — the app connects straight to your NavProMini '
          'over your local network to drive teleop, mapping, and navigation.',
    ),
    _Slide(
      icon: Icons.wifi_tethering,
      title: 'Connect once your robot is on the network',
      body:
          'Power on the robot and join the same Wi-Fi/network it\'s on. The '
          'next screen scans for it automatically — or you can enter its IP '
          'address directly.',
    ),
    _Slide(
      icon: Icons.route_outlined,
      title: 'Map, navigate, and run missions',
      body:
          'Build a map, send goals, and chain waypoints, service calls, and '
          'actions into a saved mission the robot can run start to finish.',
    ),
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OnboardingScreen.seenPrefsKey, true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ConnectionScreen()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.lightTheme,
      child: Builder(builder: (context) {
        final theme = Theme.of(context);
        final isLast = _page == _slides.length - 1;
        return Scaffold(
          backgroundColor: AppColors.lightBackground,
          body: SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: TextButton(
                      onPressed: _finish,
                      child: const Text('Skip'),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _slides.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) {
                      final slide = _slides[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xl),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                slide.icon,
                                size: 48,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            Text(
                              slide.title,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              slide.body,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _slides.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _page ? 20 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: i == _page
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: isLast
                          ? _finish
                          : () => _controller.nextPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut),
                      child: Text(isLast ? 'Get started' : 'Next'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// Decides between [OnboardingScreen] and [ConnectionScreen] based on the
/// persisted flag, without blocking `main()` on the async prefs read — a
/// brief blank frame is preferable to delaying `runApp`.
class OnboardingGate extends StatefulWidget {
  const OnboardingGate({super.key});

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  bool? _seen;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() {
        _seen = prefs.getBool(OnboardingScreen.seenPrefsKey) ?? false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_seen == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.shrink(),
      );
    }
    return _seen! ? const ConnectionScreen() : const OnboardingScreen();
  }
}
