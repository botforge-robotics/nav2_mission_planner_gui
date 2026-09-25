import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nav2_mission_planner/screens/setup/setup_scaffold.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SetupScaffold Navigation', () {
    testWidgets('renders Next and Back buttons and triggers callbacks', (tester) async {
      bool backPressed = false;
      bool nextPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: SetupScaffold(
            step: 2,
            totalSteps: 5,
            title: 'Test Step',
            subtitle: 'Testing navigation',
            primaryLabel: 'Next',
            onPrimary: () => nextPressed = true,
            onBack: () => backPressed = true,
            child: const Text('Step Content'),
          ),
        ),
      );

      // Verify content and step badge
      expect(find.text('Test Step'), findsOneWidget);
      expect(find.text('Step Content'), findsOneWidget);
      expect(find.text('Step 2 of 5'), findsOneWidget);

      // Verify Back button and Next button exist
      expect(find.text('Back'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);

      // Tap Next
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(nextPressed, isTrue);

      // Tap Back
      await tester.tap(find.text('Back'));
      await tester.pump();
      expect(backPressed, isTrue);
    });

    testWidgets('renders single primary button on step 1 when no back route exists', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SetupScaffold(
            step: 1,
            totalSteps: 5,
            title: 'Power On',
            primaryLabel: 'Next',
            showBackButton: false,
            child: const Text('Power content'),
          ),
        ),
      );

      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Back'), findsNothing);
      expect(find.text('Step 1 of 5'), findsOneWidget);
    });
  });
}
