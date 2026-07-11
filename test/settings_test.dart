import 'package:test/test.dart';
import 'package:gazoo/core/config/settings.dart';

void main() {
  test('defaults match spec: 60s idle timeout, auto-start off, light theme, onboarding unseen', () {
    expect(Settings.defaults.idleTimeout, const Duration(seconds: 60));
    expect(Settings.defaults.autoStartLastServer, isFalse);
    expect(Settings.defaults.lastServerId, isNull);
    expect(Settings.defaults.darkMode, isFalse);
    expect(Settings.defaults.verboseLogging, isFalse);
    expect(Settings.defaults.hasSeenOnboarding, isFalse);
  });

  test('copyWith overrides only the given fields', () {
    final updated = Settings.defaults.copyWith(darkMode: true, lastServerId: 'abc');
    expect(updated.darkMode, isTrue);
    expect(updated.lastServerId, 'abc');
    expect(updated.idleTimeout, Settings.defaults.idleTimeout);
    expect(updated.autoStartLastServer, Settings.defaults.autoStartLastServer);
    expect(updated.hasSeenOnboarding, Settings.defaults.hasSeenOnboarding);
  });

  test('copyWith can flip hasSeenOnboarding independently of other fields', () {
    final updated = Settings.defaults.copyWith(hasSeenOnboarding: true);
    expect(updated.hasSeenOnboarding, isTrue);
    expect(updated.darkMode, Settings.defaults.darkMode);
  });

  test('toJson/fromJson round-trips all fields', () {
    final original = Settings.defaults.copyWith(
      idleTimeout: const Duration(seconds: 30),
      autoStartLastServer: true,
      lastServerId: 'xyz',
      darkMode: true,
      verboseLogging: true,
      hasSeenOnboarding: true,
    );
    final restored = Settings.fromJson(original.toJson());
    expect(restored.idleTimeout, original.idleTimeout);
    expect(restored.autoStartLastServer, original.autoStartLastServer);
    expect(restored.lastServerId, original.lastServerId);
    expect(restored.darkMode, original.darkMode);
    expect(restored.verboseLogging, original.verboseLogging);
    expect(restored.hasSeenOnboarding, original.hasSeenOnboarding);
  });

  test('fromJson falls back to defaults for missing keys', () {
    final restored = Settings.fromJson({});
    expect(restored.idleTimeout, Settings.defaults.idleTimeout);
    expect(restored.autoStartLastServer, Settings.defaults.autoStartLastServer);
    expect(restored.lastServerId, isNull);
    expect(restored.hasSeenOnboarding, isFalse);
  });
}
