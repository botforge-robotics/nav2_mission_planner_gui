import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nav2_mission_planner/providers/connection_provider.dart';
import 'package:nav2_mission_planner/providers/robot_telemetry_provider.dart';
import 'package:nav2_mission_planner/widgets/app_shell/app_shell.dart';
import 'package:nav2_mission_planner/widgets/map/occupancy_grid_view.dart';
import 'package:provider/provider.dart';
import 'package:ros2_api/ros2_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AppShell survives resize between desktop, tablet, and mobile without assertion errors', (tester) async {
    final connectionProvider = ConnectionProvider();
    final telemetryProvider = RobotTelemetryProvider();

    // Start with desktop window size
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ConnectionProvider>.value(value: connectionProvider),
          ChangeNotifierProvider<RobotTelemetryProvider>.value(value: telemetryProvider),
        ],
        child: const MaterialApp(
          home: AppShell(),
        ),
      ),
    );

    await tester.pump();

    // Resize to tablet
    tester.view.physicalSize = const Size(768, 1024);
    await tester.pump();

    // Resize to mobile
    tester.view.physicalSize = const Size(375, 667);
    await tester.pump();

    // Resize to minimized / narrow window
    tester.view.physicalSize = const Size(320, 480);
    await tester.pump();

    // Resize back to desktop
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pump();

    expect(find.byType(AppShell), findsOneWidget);
  });

  testWidgets('OccupancyGridView switches interactive mode and survives resizing without GlobalKey assertions', (tester) async {
    final ros2 = Ros2();

    Widget buildView({required bool interactive}) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: OccupancyGridView(
              ros2: ros2,
              interactive: interactive,
            ),
          ),
        ),
      );
    }

    // Pump with interactive: true
    await tester.pumpWidget(buildView(interactive: true));
    await tester.pump(const Duration(milliseconds: 500));

    // Switch to interactive: false
    await tester.pumpWidget(buildView(interactive: false));
    await tester.pump(const Duration(milliseconds: 500));

    // Switch back to interactive: true
    await tester.pumpWidget(buildView(interactive: true));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(OccupancyGridView), findsOneWidget);

    // Clean up
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  });
}
