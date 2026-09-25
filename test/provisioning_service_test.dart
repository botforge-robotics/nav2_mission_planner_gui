import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nav2_mission_planner/services/provisioning_service.dart';

void main() {
  group('ProvisioningService', () {
    late HttpServer server;
    late int serverPort;
    Map<String, String>? lastReceivedBody;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      serverPort = server.port;
      lastReceivedBody = null;

      server.listen((HttpRequest request) async {
        if (request.uri.path == '/save' && request.method == 'POST') {
          final content = await utf8.decoder.bind(request).join();
          final pairs = Uri.splitQueryString(content);
          lastReceivedBody = pairs;
          request.response
            ..statusCode = HttpStatus.ok
            ..write('OK');
          await request.response.close();
        } else if (request.uri.path == '/api/status') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'phase': 'idle', 'message': ''}));
          await request.response.close();
        }
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('submit correctly encodes wifi credentials, country code, and timezone', () async {
      final service = ProvisioningService(portalBase: 'http://127.0.0.1:$serverPort');

      await service.submit(
        wifiSsid: 'Office-WiFi',
        wifiPassword: 'SecretPassword123',
        robotName: 'TestBot-99',
        timezone: 'Asia/Kolkata',
        countryCode: 'IN',
      );

      expect(lastReceivedBody, isNotNull);
      expect(lastReceivedBody!['wifi_ssid'], 'Office-WiFi');
      expect(lastReceivedBody!['wifi_password'], 'SecretPassword123');
      expect(lastReceivedBody!['robot_name'], 'TestBot-99');
      expect(lastReceivedBody!['timezone'], 'Asia/Kolkata');
      expect(lastReceivedBody!['country_code'], 'IN');
    });
  });
}
