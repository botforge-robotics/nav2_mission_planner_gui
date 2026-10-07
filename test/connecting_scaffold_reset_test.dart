import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:nav2_mission_planner/providers/connection_provider.dart';
import 'package:nav2_mission_planner/providers/setup_flow_controller.dart';
import 'package:nav2_mission_planner/screens/setup/setup_power_screen.dart';
import 'package:nav2_mission_planner/widgets/connecting_scaffold.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Reset and Set Up New Robot navigates cleanly to SetupPowerScreen on connection error', (tester) async {
    final connection = ConnectionProvider();
    connection.error = 'Lost connection to navpromini (192.168.0.128)';

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SetupFlowController()),
          ChangeNotifierProvider.value(value: connection),
        ],
        child: MaterialApp(
          home: ConnectingScaffold(connection: connection),
        ),
      ),
    );

    expect(find.text('Connection Lost'), findsOneWidget);
    expect(find.text('Reset & Set Up New Robot'), findsOneWidget);

    await tester.tap(find.text('Reset & Set Up New Robot'));
    await tester.pumpAndSettle();

    // Verify it navigated to SetupPowerScreen
    expect(find.byType(SetupPowerScreen), findsOneWidget);
    expect(find.text('Power on Your Robot'), findsOneWidget);
  });

  testWidgets('Reset button navigates cleanly to SetupPowerScreen from connecting state', (tester) async {
    final connection = ConnectionProvider();
    connection.error = null;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SetupFlowController()),
          ChangeNotifierProvider.value(value: connection),
        ],
        child: MaterialApp(
          home: ConnectingScaffold(connection: connection),
        ),
      ),
    );

    expect(find.text('Reset'), findsOneWidget);

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(find.byType(SetupPowerScreen), findsOneWidget);
    expect(find.text('Power on Your Robot'), findsOneWidget);
  });
}
