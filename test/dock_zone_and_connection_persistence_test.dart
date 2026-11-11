import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nav2_mission_planner/providers/connection_provider.dart';
import 'package:nav2_mission_planner/providers/robot_telemetry_provider.dart';
import 'package:nav2_mission_planner/screens/teleop/teleop_screen.dart';
import 'package:nav2_mission_planner/services/gamepad_service.dart';
import 'package:nav2_mission_planner/services/robot_connection_store.dart';
import 'package:nav2_mission_planner/widgets/teleop/drive_pad.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConnectionProvider Lifecycle & Persistence Tests', () {
    test('ConnectionProvider implements WidgetsBindingObserver and handles resumed state', () {
      final conn = ConnectionProvider();
      expect(conn.hasConnectedOnce, isFalse);
      expect(conn.isConnected, isFalse);

      // Verify lifecycle call does not crash
      conn.didChangeAppLifecycleState(AppLifecycleState.resumed);
      conn.didChangeAppLifecycleState(AppLifecycleState.paused);
      conn.dispose();
    });
  });

  group('GamepadService Dock Zone Lock Tests', () {
    test('GamepadService updates isDockZoneLocked correctly', () {
      final gamepad = GamepadService.instance;
      expect(gamepad.isDockZoneLocked, isFalse);

      gamepad.updateConnection(isDockZoneLocked: true);
      expect(gamepad.isDockZoneLocked, isTrue);

      gamepad.updateConnection(isDockZoneLocked: false);
      expect(gamepad.isDockZoneLocked, isFalse);
    });
  });

  group('TeleopScreen Dock Zone Interlock UI Tests', () {
    testWidgets('DrivePad remains fully visible when dock zone interlock is active', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final conn = ConnectionProvider();
      conn.robot = const SavedRobot(name: 'navpromini', ip: '192.168.0.128');
      final telemetry = RobotTelemetryProvider();
      telemetry.inDockZone = true;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ConnectionProvider>.value(value: conn),
            ChangeNotifierProvider<RobotTelemetryProvider>.value(value: telemetry),
          ],
          child: const MaterialApp(
            home: TeleopScreen(),
          ),
        ),
      );

      await tester.pump();

      // Verify DrivePad is present and visible
      expect(find.byType(DrivePad), findsOneWidget);

      // Verify Dock Zone Safety Interlock banner is rendered
      expect(find.text('Dock Zone Safety Interlock'), findsOneWidget);
      expect(find.text('LOCKED'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Undock'), findsOneWidget);

      // Verify there is NO full-screen blocking overlay obscuring the controls
      expect(find.text('Manual teleop is locked in the dock zone to protect charger contacts. Undock robot to drive.'), findsNothing);
    });
  });
}
