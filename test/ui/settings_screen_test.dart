import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gazoo/ui/screens/settings_screen.dart';
import 'package:gazoo/ui/state/app_log.dart';
import 'package:gazoo/ui/state/settings_notifier.dart';

Widget _app(SettingsNotifier settingsNotifier, AppLog appLog) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settingsNotifier),
      ChangeNotifierProvider.value(value: appLog),
    ],
    child: const MaterialApp(home: SettingsScreen()),
  );
}

void main() {
  late SettingsNotifier notifier;
  late AppLog appLog;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    notifier = SettingsNotifier(prefs: prefs);
    appLog = AppLog();
  });

  testWidgets('toggling dark mode updates the notifier', (tester) async {
    await tester.pumpWidget(_app(notifier, appLog));

    await tester.tap(find.byKey(const Key('dark-mode-switch')));
    await tester.pumpAndSettle();

    expect(notifier.settings.darkMode, isTrue);
  });

  testWidgets('toggling auto-start updates the notifier', (tester) async {
    await tester.pumpWidget(_app(notifier, appLog));

    await tester.tap(find.byKey(const Key('auto-start-switch')));
    await tester.pumpAndSettle();

    expect(notifier.settings.autoStartLastServer, isTrue);
  });

  testWidgets('log panel is hidden until the log-panel switch is on', (tester) async {
    await tester.pumpWidget(_app(notifier, appLog));

    expect(find.byKey(const Key('log-panel')), findsNothing);

    await tester.tap(find.byKey(const Key('log-panel-switch')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('log-panel')), findsOneWidget);
  });

  testWidgets('log panel shows lines from AppLog', (tester) async {
    appLog.append('hello from core');
    await tester.pumpWidget(_app(notifier, appLog));

    await tester.tap(find.byKey(const Key('log-panel-switch')));
    await tester.pumpAndSettle();

    expect(find.text('hello from core'), findsOneWidget);
  });

  testWidgets('Help entry navigates to Onboarding with no Get Started button', (tester) async {
    await tester.pumpWidget(_app(notifier, appLog));

    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Gazoo'), findsOneWidget);
    expect(find.byKey(const Key('get-started-button')), findsNothing);
  });

  testWidgets('idle timeout dropdown offers the full 10s-10min range', (tester) async {
    await tester.pumpWidget(_app(notifier, appLog));

    await tester.tap(find.byKey(const Key('idle-timeout-dropdown')));
    await tester.pumpAndSettle();

    expect(find.text('10s'), findsOneWidget);
    expect(find.text('600s'), findsOneWidget);
  });
}
