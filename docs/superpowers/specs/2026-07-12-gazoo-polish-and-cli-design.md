# Gazoo: Platform Polish & Headless CLI — Design

## Goal

Close the remaining fully-automatable gaps identified in the final GUI-layer review and the user's follow-up: an iOS permission declaration, a fixed race condition, clearer error messages, two deferred UI polish items, and the headless CLI flag the core/UI split was designed to support. Explicitly excludes Android foreground service/multicast lock and iOS `Network.framework` fallback validation — both require real-device verification this session cannot perform and get their own milestone once hardware is available.

## Scope (6 independent, small changes)

1. **iOS `NSLocalNetworkUsageDescription`** — add to `ios/Runner/Info.plist` so iOS's local-network permission prompt actually fires; without it, UDP broadcast/receive may be silently blocked.
2. **`RelayNotifier` start/stop race fix** — `ActiveRelayScreen.dispose()` fires `stop()` unawaited (State.dispose() can't be async); if the user navigates to a new server before that teardown finishes, `start()`'s `_service != null` guard doesn't protect against the in-flight stop. Add a `_stopping` future guard so `start()` waits out any in-flight `stop()` before proceeding.
3. **Clear relay-start error messages** — map common `SocketException`/`StateError` cases (port already in use, permission denied, host not found) to specific user-facing text instead of the raw `$error` interpolation, per the original spec's "handle common failure modes explicitly" requirement.
4. **Idle-timeout range** — widen the Settings dropdown from `[30, 60, 120, 300]` to `[10, 30, 60, 120, 300, 600]` to match the original spec's stated 10s–10min range.
5. **Byte-counter pulse** — cross-fade the byte-counter text via `AnimatedSwitcher` keyed on the current byte counts, giving the "brief pulse on each change" the original spec asked for, without a custom `AnimationController`.
6. **Headless CLI** — `lib/cli/headless_runner.dart`: a pure, testable `parseHeadlessArgs(List<String> args)` function and a `runHeadless(HeadlessArgs)` that drives `RelayService` directly with stdout logging, exiting cleanly on SIGINT. `main(List<String> args)` checks for `--headless` before any Flutter binding/UI setup.

## Testing

Same conventions as prior milestones: `parseHeadlessArgs` gets `package:test` unit tests (pure Dart, no Flutter); the notifier/screen changes get `flutter_test` widget/unit tests using the same fake-`RelayServiceHandle` pattern already established.

## Out of Scope

Android foreground service, multicast lock, permission manifest entries; iOS `Network.framework` fallback; desktop firewall auto-detection (Onboarding's existing static text already covers the guidance); real console hardware validation.
