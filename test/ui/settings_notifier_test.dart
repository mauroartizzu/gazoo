import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gazoo/core/config/settings.dart';
import 'package:gazoo/ui/state/settings_notifier.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('starts with Settings.defaults when nothing persisted', () {
    final notifier = SettingsNotifier(prefs: prefs);
    expect(notifier.settings.idleTimeout, Settings.defaults.idleTimeout);
    expect(notifier.settings.hasSeenOnboarding, isFalse);
  });

  test('update persists and notifies listeners; a fresh instance reloads it', () async {
    final notifier = SettingsNotifier(prefs: prefs);
    var notified = 0;
    notifier.addListener(() => notified++);

    await notifier.update((s) => s.copyWith(darkMode: true, hasSeenOnboarding: true));

    expect(notifier.settings.darkMode, isTrue);
    expect(notifier.settings.hasSeenOnboarding, isTrue);
    expect(notified, greaterThan(0));

    final reloaded = SettingsNotifier(prefs: prefs);
    expect(reloaded.settings.darkMode, isTrue);
    expect(reloaded.settings.hasSeenOnboarding, isTrue);
  });

  test('update only changes the fields the updater touches', () async {
    final notifier = SettingsNotifier(prefs: prefs);
    await notifier.update((s) => s.copyWith(darkMode: true));
    await notifier.update((s) => s.copyWith(verboseLogging: true));

    expect(notifier.settings.darkMode, isTrue);
    expect(notifier.settings.verboseLogging, isTrue);
  });
}
