import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gazoo/main.dart';
import 'package:gazoo/ui/state/app_log.dart';
import 'package:gazoo/ui/state/relay_notifier.dart';
import 'package:gazoo/ui/state/server_list_notifier.dart';
import 'package:gazoo/ui/state/settings_notifier.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Widget appWith({required bool hasSeenOnboarding}) {
    final settingsNotifier = SettingsNotifier(prefs: prefs);
    if (hasSeenOnboarding) {
      settingsNotifier.update((s) => s.copyWith(hasSeenOnboarding: true));
    }
    return GazooApp(
      appLog: AppLog(),
      serverListNotifier: ServerListNotifier(prefs: prefs),
      settingsNotifier: settingsNotifier,
      relayNotifier: RelayNotifier(),
    );
  }

  testWidgets('shows Onboarding when hasSeenOnboarding is false', (tester) async {
    await tester.pumpWidget(appWith(hasSeenOnboarding: false));
    await tester.pump();

    expect(find.text('Welcome to Gazoo'), findsOneWidget);
  });

  testWidgets('shows the home shell (Server List by default) when onboarding is done', (tester) async {
    await tester.pumpWidget(appWith(hasSeenOnboarding: true));
    await tester.pumpAndSettle();

    expect(find.text('Gazoo Servers'), findsOneWidget);
  });

  testWidgets('narrow width shows NavigationBar; switching tabs shows Settings', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(appWith(hasSeenOnboarding: true));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('wide width shows NavigationRail instead of NavigationBar', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(appWith(hasSeenOnboarding: true));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
