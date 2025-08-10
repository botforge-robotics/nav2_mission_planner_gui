import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/licensing_provider.dart';
import '../../providers/branding_provider.dart';
import '../auth/login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../connection_screen.dart';
import 'trial_or_purchase_screen.dart';

class LicensingGate extends StatefulWidget {
  const LicensingGate({super.key});

  @override
  State<LicensingGate> createState() => _LicensingGateState();
}

class _LicensingGateState extends State<LicensingGate> {
  bool _refreshedAfterLogin = false;
  bool _didInitialCacheCheck = false;
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final provider = context.read<LicensingProvider>();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final usedCache = await provider.tryLoadFromCache();
        if (!usedCache) {
          await provider.refresh();
        } else {
          // background refresh
          provider.refresh();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null) {
          _refreshedAfterLogin = false;
          _didInitialCacheCheck = false;
          return const LoginScreen();
        }
        // On first auth'd frame: prefer cached license for offline grace; only refresh if no cache
        if (!_refreshedAfterLogin && !_didInitialCacheCheck) {
          _refreshedAfterLogin = true;
          Future.microtask(() async {
            final lp = context.read<LicensingProvider>();
            final usedCache = await lp.tryLoadFromCache();
            _didInitialCacheCheck = true;
            if (!usedCache) {
              await lp.refresh();
            }
            // If cache used, rely on background checks elsewhere or manual actions
          });
        }
        return Consumer<LicensingProvider>(builder: (context, lp, _) {
          print('🎭 LicensingGate Consumer rebuild - State: ${lp.state}');
          switch (lp.state) {
            case LicenseGateState.loading:
              print('⏳ Showing loading screen');
              final brand = context.read<BrandingProvider>().themeColor;
              return Scaffold(
                body: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        brand.withOpacity(0.15),
                        Colors.black.withOpacity(0.6),
                      ],
                    ),
                  ),
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(brand),
                    ),
                  ),
                ),
              );
            case LicenseGateState.licenseActive:
            case LicenseGateState.trialActive:
              print('✅ Showing ConnectionScreen for active license/trial');
              return const ConnectionScreen();
            case LicenseGateState.noLicense:
            case LicenseGateState.trialExpired:
            case LicenseGateState.linkedToOtherDevice:
            case LicenseGateState.licenseRevoked:
            case LicenseGateState.error:
              print('🎯 Showing TrialOrPurchaseScreen for state: ${lp.state}');
              return TrialOrPurchaseScreen(
                  state: lp.state,
                  message: lp.statusMessage,
                  linkedDeviceId: lp.linkedDeviceId);
          }
        });
      },
    );
  }
}
