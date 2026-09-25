import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nav2_mission_planner/services/wifi_join_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WifiJoinService', () {
    final service = WifiJoinService();

    test('verifies constants match robot config', () {
      expect(kSetupHotspotPrefix, 'NavPro-Setup-');
      expect(kSetupHotspotPassword, 'navprosetup');
      expect(kSetupHotspotGatewayIp, '10.42.0.1');
    });

    test('canScan returns true on Linux desktop when nmcli is available', () async {
      if (Platform.isLinux) {
        final can = await service.canScan();
        expect(can, isTrue);
      }
    });

    test('scanForSetupHotspots parses and returns NavPro-Setup hotspots on Linux', () async {
      if (Platform.isLinux) {
        final hotspots = await service.scanForSetupHotspots();
        // If the robot AP is live nearby, it must start with NavPro-Setup-
        for (final hotspot in hotspots) {
          expect(hotspot.startsWith(kSetupHotspotPrefix), isTrue);
        }
        // Cached site networks should not contain the setup hotspot prefix
        for (final siteNet in service.cachedSiteNetworks) {
          expect(siteNet.startsWith(kSetupHotspotPrefix), isFalse);
        }
      }
    });
  });
}
