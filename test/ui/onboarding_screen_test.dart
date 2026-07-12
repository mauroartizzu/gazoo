import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gazoo/ui/screens/onboarding_screen.dart';
import 'package:gazoo/ui/state/settings_notifier.dart';

void main() {
  late SettingsNotifier notifier;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    notifier = SettingsNotifier(prefs: prefs);
  });

  testWidgets('shows Get Started button by default and sets hasSeenOnboarding on tap', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: notifier,
        child: const MaterialApp(home: OnboardingScreen()),
      ),
    );

    expect(find.byKey(const Key('get-started-button')), findsOneWidget);
    expect(notifier.settings.hasSeenOnboarding, isFalse);

    await tester.tap(find.byKey(const Key('get-started-button')));
    await tester.pumpAndSettle();

    expect(notifier.settings.hasSeenOnboarding, isTrue);
  });

  testWidgets('shows a Close button instead when reached from Settings (showGetStarted: false)', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: notifier,
        child: const MaterialApp(home: OnboardingScreen(showGetStarted: false)),
      ),
    );

    expect(find.byKey(const Key('get-started-button')), findsNothing);
    expect(find.text('Close'), findsOneWidget);
  });
}
