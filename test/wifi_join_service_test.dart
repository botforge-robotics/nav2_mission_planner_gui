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
    test('buildWlanProfileXml generates valid WLANProfile XML with correct hex and security', () {
      final xml = WifiJoinService.buildWlanProfileXml('NavPro-Setup-12AB34');
      expect(xml, contains('<name>NavPro-Setup-12AB34</name>'));
      expect(xml, contains('<hex>4E617650726F2D53657475702D313241423334</hex>'));
      expect(xml, contains('<authentication>WPA2PSK</authentication>'));
      expect(xml, contains('<encryption>AES</encryption>'));
      expect(xml, contains('<keyMaterial>navprosetup</keyMaterial>'));
    });

    test('parseNetshNetworks parses mode=bssid output and sorts by signal strength', () {
      const netshOutput = '''
Interface name : Wi-Fi
There are 4 networks currently visible.

SSID 1 : Office_Guest
    Network type            : Infrastructure
    Authentication          : WPA2-Personal
    Encryption              : CCMP
    BSSID 1                 : 00:11:22:33:44:55
         Signal             : 60%

SSID 2 : NavPro-Setup-WEAK
    Network type            : Infrastructure
    Authentication          : WPA2-Personal
    Encryption              : CCMP
    BSSID 1                 : aa:bb:cc:dd:ee:ff
         Signal             : 45%

SSID 3 : NavPro-Setup-STRONG
    Network type            : Infrastructure
    Authentication          : WPA2-Personal
    Encryption              : CCMP
    BSSID 1                 : 11:22:33:44:55:66
         Signal             : 92%

SSID 4 : Office_Main
    Network type            : Infrastructure
    Authentication          : WPA2-Personal
    Encryption              : CCMP
    BSSID 1                 : 77:88:99:aa:bb:cc
         Signal             : 85%
''';

      final result = WifiJoinService.parseNetshNetworks(netshOutput);

      expect(result.hotspots, ['NavPro-Setup-STRONG', 'NavPro-Setup-WEAK']);
      expect(result.siteNetworks, ['Office_Main', 'Office_Guest']);
    });

    test('parseNetshInterfaceSsid extracts active connected SSID and ignores disconnected', () {
      const connectedOutput = '''
There is 1 interface on the system:

    Name                   : Wi-Fi
    Description            : Intel(R) Wi-Fi 6 AX201 160MHz
    State                  : connected
    SSID                   : NavPro-Setup-12AB34
    BSSID                  : 00:11:22:33:44:55
    Network type           : Infrastructure
''';

      const disconnectedOutput = '''
There is 1 interface on the system:

    Name                   : Wi-Fi
    Description            : Intel(R) Wi-Fi 6 AX201 160MHz
    State                  : disconnected
''';

      expect(
        WifiJoinService.parseNetshInterfaceSsid(connectedOutput),
        'NavPro-Setup-12AB34',
      );
      expect(
        WifiJoinService.parseNetshInterfaceSsid(disconnectedOutput),
        isNull,
      );
    });
  });
}
