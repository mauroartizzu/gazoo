# Gazoo Platform Polish & Headless CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close 6 small, independent gaps: iOS local-network permission declaration, a `RelayNotifier` start/stop race, clearer relay-start error messages, a wider idle-timeout range, a byte-counter pulse animation, and a headless CLI mode.

**Architecture:** No new architecture — each task is a small, targeted change to an existing file (or one new pure-Dart CLI module), following the exact patterns already established in the core and GUI milestones.

**Tech Stack:** Same as prior milestones — Flutter 3.44.6, `package:test` for pure-Dart logic, `flutter_test` for widget/notifier tests.

## Global Constraints

- No new third-party dependencies — `parseHeadlessArgs` does manual flag parsing, not the `args` package.
- `lib/core/` stays free of `package:flutter` imports; `lib/cli/` may use `dart:io` but not Flutter.
- Do not touch Android or iOS `Network.framework` platform glue — out of scope per the design spec.

---

### Task 1: iOS local-network permission declaration

**Files:**
- Modify: `ios/Runner/Info.plist`

**Interfaces:** None — a plist entry, no code.

- [ ] **Step 1: Add the permission string**

Edit `ios/Runner/Info.plist`. Directly above the closing `</dict>` (before the final `</dict>\n</plist>`), add:

```xml
	<key>NSLocalNetworkUsageDescription</key>
	<string>Gazoo needs local network access to make a remote Minecraft server appear as a LAN game to your console and relay its traffic.</string>
```

- [ ] **Step 2: Verify the plist is still well-formed XML**

```bash
plutil -lint ios/Runner/Info.plist
```

Expected: `ios/Runner/Info.plist: OK`

- [ ] **Step 3: Commit**

```bash
git add ios/Runner/Info.plist
git commit -m "Add NSLocalNetworkUsageDescription for iOS local network permission"
```

---

### Task 2: Fix `RelayNotifier` start/stop race

**Files:**
- Modify: `lib/ui/state/relay_notifier.dart`
- Modify: `test/ui/relay_notifier_test.dart`

**Interfaces:**
- Consumes: nothing new
- Produces: `RelayNotifier.start()` now safely waits out any in-flight `stop()` before proceeding — no new public members, existing signatures unchanged.

- [ ] **Step 1: Write the failing test**

Add this test case inside the existing `main()` function body in `test/ui/relay_notifier_test.dart` (alongside the existing 6 tests — do not remove or modify them):

```dart
  test('start() waits out an in-flight stop() before proceeding, avoiding the double-active-service race', () async {
    final fakeA = _FakeRelayService();
    final fakeB = _FakeRelayService();
    var callCount = 0;
    final services = [fakeA, fakeB];
    final notifier = RelayNotifier(createRelayService: () => services[callCount++]);

    await notifier.start(sampleServer());

    // Fire-and-forget stop (mirrors ActiveRelayScreen.dispose(), which can't await),
    // then immediately start again for a different server — this used to race.
    final stopFuture = notifier.stop();
    final secondServer = ServerConfig.create(
      name: 'Second', host: 'example.com', port: 19132, proxyPort: 19134,
    );
    await notifier.start(secondServer);
    await stopFuture;

    expect(fakeA.disposed, isTrue);
    expect(notifier.isRunning, isTrue);
    expect(notifier.activeServer, secondServer);
  });
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/ui/relay_notifier_test.dart
```

Expected: FAIL — without the guard, the second `start()` either throws `StateError` (if the first `stop()` hasn't nulled `_service` yet) or races unpredictably.

- [ ] **Step 3: Add the `_stopping` guard**

Modify `lib/ui/state/relay_notifier.dart`. Add a field:

```dart
  Future<void>? _stopping;
```

(add it directly below `RelayEvent? _lastEvent;`). Change `start()` to wait out any in-flight stop first:

```dart
  Future<void> start(ServerConfig server) async {
    if (_stopping != null) {
      await _stopping;
    }
    if (_service != null) {
      throw StateError('RelayNotifier already running; call stop() first');
    }
    final service = createRelayService();
    _service = service;
    _activeServer = server;
    onStart?.call(server);
    _lastEvent = null;
    _subscription = service.events.listen((event) {
      _lastEvent = event;
      notifyListeners();
    });
    notifyListeners();
    await service.start([server]);
  }
```

Change `stop()` to track its own in-flight future so concurrent callers (and the new `start()` guard) can await it exactly once:

```dart
  Future<void> stop() async {
    final service = _service;
    if (service == null) return;
    final future = _stopInternal(service);
    _stopping = future;
    await future;
    _stopping = null;
  }

  Future<void> _stopInternal(RelayServiceHandle service) async {
    await _subscription?.cancel();
    _subscription = null;
    await service.dispose();
    _service = null;
    _activeServer = null;
    _lastEvent = null;
    notifyListeners();
  }
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/ui/relay_notifier_test.dart
```

Expected: PASS — all 7 tests (6 existing + 1 new) green.

- [ ] **Step 5: Run the full suite**

```bash
flutter analyze
flutter test
```

Expected: analyze clean, full suite green (80 + 1 = 81 or however many the current total is).

- [ ] **Step 6: Commit**

```bash
git add lib/ui/state/relay_notifier.dart test/ui/relay_notifier_test.dart
git commit -m "Fix RelayNotifier start/stop race with a _stopping guard"
```

---

### Task 3: Clear relay-start error messages

**Files:**
- Modify: `lib/ui/screens/active_relay_screen.dart`
- Modify: `test/ui/active_relay_screen_test.dart`

**Interfaces:**
- Consumes: `dart:io`'s `SocketException`
- Produces: a private `String _friendlyStartError(Object error)` helper used only within this file — no new public API.

- [ ] **Step 1: Write the failing test**

Add these test cases inside the existing `main()` function body in `test/ui/active_relay_screen_test.dart` (alongside the existing 3 tests — do not remove or modify them). First, add a fake that throws on `start()`:

```dart
class _ThrowingRelayService implements RelayServiceHandle {
  final Object errorToThrow;
  _ThrowingRelayService(this.errorToThrow);

  @override
  Stream<RelayEvent> get events => const Stream.empty();

  @override
  Future<void> start(List<ServerConfig> servers) async {
    throw errorToThrow;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
```

Then the test cases:

```dart
  testWidgets('shows a specific message when the port is already in use', (tester) async {
    final relayNotifier = RelayNotifier(
      createRelayService: () => _ThrowingRelayService(
        const SocketException('Address already in use', osError: null),
      ),
    );
    final server = sampleServer();

    await tester.pumpWidget(_harness(relayNotifier, server));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('already in use'), findsOneWidget);
  });

  testWidgets('shows a specific message when permission is denied', (tester) async {
    final relayNotifier = RelayNotifier(
      createRelayService: () => _ThrowingRelayService(
        const SocketException('Permission denied', osError: null),
      ),
    );
    final server = sampleServer();

    await tester.pumpWidget(_harness(relayNotifier, server));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Permission denied'), findsOneWidget);
  });

  testWidgets('shows a specific message when the host cannot be found', (tester) async {
    final relayNotifier = RelayNotifier(
      createRelayService: () => _ThrowingRelayService(
        const SocketException('Failed host lookup: \'nonexistent.example\'', osError: null),
      ),
    );
    final server = sampleServer();

    await tester.pumpWidget(_harness(relayNotifier, server));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not find'), findsOneWidget);
  });
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/ui/active_relay_screen_test.dart
```

Expected: FAIL — the current handler just shows `'Failed to start relay: $error'`, so `findsOneWidget` for `'already in use'`/`'Permission denied'`/`'Could not find'` fails (the raw `SocketException.toString()` output doesn't contain that exact phrasing).

- [ ] **Step 3: Add the friendly-error mapping**

Modify `lib/ui/screens/active_relay_screen.dart`. Add this private top-level function at the bottom of the file (after the `_ActiveRelayScreenState` class):

```dart
String _friendlyStartError(Object error) {
  if (error is SocketException) {
    final message = error.message.toLowerCase();
    if (message.contains('already in use')) {
      return 'Port already in use — another app (or another Gazoo instance) may already be using this port.';
    }
    if (message.contains('permission denied')) {
      return 'Permission denied opening the network port. Check your firewall settings.';
    }
    if (message.contains('failed host lookup') || message.contains('no address associated')) {
      return 'Could not find the server host. Check the host/IP address.';
    }
    return 'Network error: ${error.message}';
  }
  if (error is StateError) {
    return error.message;
  }
  return 'Failed to start relay: $error';
}
```

Then change the `catchError` call in `initState()` from:

```dart
      context.read<RelayNotifier>().start(widget.server).catchError((Object error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to start relay: $error')),
          );
        }
      });
```

to:

```dart
      context.read<RelayNotifier>().start(widget.server).catchError((Object error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_friendlyStartError(error))),
          );
        }
      });
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/ui/active_relay_screen_test.dart
```

Expected: PASS — all 6 tests (3 existing + 3 new) green.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/screens/active_relay_screen.dart test/ui/active_relay_screen_test.dart
git commit -m "Map relay-start errors to clear, specific user-facing messages"
```

---

### Task 4: Widen the idle-timeout range

**Files:**
- Modify: `lib/ui/screens/settings_screen.dart`
- Modify: `test/ui/settings_screen_test.dart`

**Interfaces:** None new — same `SettingsNotifier` interface, just a wider preset list.

- [ ] **Step 1: Write the failing test**

Add this test case inside the existing `main()` function body in `test/ui/settings_screen_test.dart` (alongside the existing 5 tests — do not remove or modify them):

```dart
  testWidgets('idle timeout dropdown offers the full 10s-10min range', (tester) async {
    await tester.pumpWidget(_app(notifier, appLog));

    await tester.tap(find.byKey(const Key('idle-timeout-dropdown')));
    await tester.pumpAndSettle();

    expect(find.text('10s'), findsOneWidget);
    expect(find.text('600s'), findsOneWidget);
  });
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/ui/settings_screen_test.dart
```

Expected: FAIL — `10s`/`600s` aren't in the current `[30, 60, 120, 300]` list.

- [ ] **Step 3: Widen the range**

Modify `lib/ui/screens/settings_screen.dart`. Change:

```dart
              items: const [30, 60, 120, 300]
```

to:

```dart
              items: const [10, 30, 60, 120, 300, 600]
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/ui/settings_screen_test.dart
```

Expected: PASS — all 6 tests (5 existing + 1 new) green.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/screens/settings_screen.dart test/ui/settings_screen_test.dart
git commit -m "Widen idle timeout dropdown to the full 10s-10min range"
```

---

### Task 5: Byte-counter pulse animation

**Files:**
- Modify: `lib/ui/screens/active_relay_screen.dart`
- Modify: `test/ui/active_relay_screen_test.dart`

**Interfaces:** None new — purely a visual change to the existing byte-counter `Text`.

- [ ] **Step 1: Write the failing test**

Add this test case inside the existing `main()` function body in `test/ui/active_relay_screen_test.dart` (alongside the other tests):

```dart
  testWidgets('byte counter cross-fades via AnimatedSwitcher when counts change', (tester) async {
    final fake = _FakeRelayService();
    final relayNotifier = RelayNotifier(createRelayService: () => fake);
    final server = sampleServer();

    await tester.pumpWidget(_harness(relayNotifier, server));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(AnimatedSwitcher), findsOneWidget);

    fake.emit(RelayEvent(
      serverId: server.id, status: RelayStatus.listening, bytesIn: 10, bytesOut: 5,
    ));
    await tester.pump();
    expect(find.textContaining('5 B'), findsOneWidget);

    fake.emit(RelayEvent(
      serverId: server.id, status: RelayStatus.listening, bytesIn: 20, bytesOut: 15,
    ));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('15 B'), findsOneWidget);
  });
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/ui/active_relay_screen_test.dart
```

Expected: FAIL — `find.byType(AnimatedSwitcher)` finds nothing yet.

- [ ] **Step 3: Wrap the byte counter in `AnimatedSwitcher`**

Modify `lib/ui/screens/active_relay_screen.dart`. Change:

```dart
            Text('↑ ${event?.bytesOut ?? 0} B   ↓ ${event?.bytesIn ?? 0} B'),
```

to:

```dart
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                '↑ ${event?.bytesOut ?? 0} B   ↓ ${event?.bytesIn ?? 0} B',
                key: ValueKey('${event?.bytesOut ?? 0}-${event?.bytesIn ?? 0}'),
              ),
            ),
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/ui/active_relay_screen_test.dart
```

Expected: PASS — all tests in this file green (the 6 from Task 3 plus this one = 7).

- [ ] **Step 5: Run the full suite**

```bash
flutter analyze
flutter test
```

Expected: analyze clean, full suite green.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/screens/active_relay_screen.dart test/ui/active_relay_screen_test.dart
git commit -m "Add byte-counter pulse via AnimatedSwitcher on count change"
```

---

### Task 6: Headless CLI mode

**Files:**
- Create: `lib/cli/headless_runner.dart`
- Test: `test/cli/headless_runner_test.dart`
- Modify: `lib/main.dart`

**Interfaces:**
- Consumes: `ServerConfig` (`lib/core/config/server_config.dart`), `RelayService` (`lib/core/relay/relay_service.dart`)
- Produces: `class HeadlessArgs { final String host; final int port; final String name; final int proxyPort; }`, `class HeadlessArgsError implements Exception { final String message; }`, `HeadlessArgs? parseHeadlessArgs(List<String> args)` (throws `HeadlessArgsError`, never calls `exit()`), `Future<void> runHeadless(HeadlessArgs args)`.

- [ ] **Step 1: Write the failing test**

Create `test/cli/headless_runner_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:gazoo/cli/headless_runner.dart';

void main() {
  test('returns null when --headless is not present', () {
    expect(parseHeadlessArgs(['--server=example.com:19132']), isNull);
    expect(parseHeadlessArgs([]), isNull);
  });

  test('parses host and port from --server', () {
    final args = parseHeadlessArgs(['--headless', '--server=example.com:19132']);
    expect(args, isNotNull);
    expect(args!.host, 'example.com');
    expect(args.port, 19132);
  });

  test('applies default name and proxy port when not specified', () {
    final args = parseHeadlessArgs(['--headless', '--server=example.com:19132']);
    expect(args!.name, 'Gazoo Server');
    expect(args.proxyPort, 19133);
  });

  test('parses --name and --proxy-port overrides', () {
    final args = parseHeadlessArgs([
      '--headless',
      '--server=example.com:19132',
      '--name=My Server',
      '--proxy-port=19140',
    ]);
    expect(args!.name, 'My Server');
    expect(args.proxyPort, 19140);
  });

  test('throws HeadlessArgsError when --server is missing', () {
    expect(
      () => parseHeadlessArgs(['--headless']),
      throwsA(isA<HeadlessArgsError>()),
    );
  });

  test('throws HeadlessArgsError when --server is malformed (no colon)', () {
    expect(
      () => parseHeadlessArgs(['--headless', '--server=example.com']),
      throwsA(isA<HeadlessArgsError>()),
    );
  });

  test('throws HeadlessArgsError when the port is not numeric', () {
    expect(
      () => parseHeadlessArgs(['--headless', '--server=example.com:notaport']),
      throwsA(isA<HeadlessArgsError>()),
    );
  });

  test('ignores unrelated arguments', () {
    final args = parseHeadlessArgs(['--some-other-flag', '--headless', '--server=example.com:19132']);
    expect(args, isNotNull);
    expect(args!.host, 'example.com');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/cli/headless_runner_test.dart
```

Expected: FAIL — cannot resolve `package:gazoo/cli/headless_runner.dart`.

- [ ] **Step 3: Write the implementation**

Create `lib/cli/headless_runner.dart`:

```dart
import 'dart:async';
import 'dart:io';

import '../core/config/server_config.dart';
import '../core/relay/relay_service.dart';

class HeadlessArgsError implements Exception {
  final String message;
  const HeadlessArgsError(this.message);

  @override
  String toString() => message;
}

class HeadlessArgs {
  final String host;
  final int port;
  final String name;
  final int proxyPort;

  const HeadlessArgs({
    required this.host,
    required this.port,
    this.name = 'Gazoo Server',
    this.proxyPort = 19133,
  });
}

/// Parses `--headless --server=host:port [--name=...] [--proxy-port=...]`.
/// Returns null if `--headless` is not present (caller should fall back to
/// the normal GUI). Throws [HeadlessArgsError] on malformed headless args —
/// never calls `exit()`, so this function stays unit-testable.
HeadlessArgs? parseHeadlessArgs(List<String> args) {
  if (!args.contains('--headless')) return null;

  String? server;
  var name = 'Gazoo Server';
  var proxyPort = 19133;

  for (final arg in args) {
    if (arg.startsWith('--server=')) {
      server = arg.substring('--server='.length);
    } else if (arg.startsWith('--name=')) {
      name = arg.substring('--name='.length);
    } else if (arg.startsWith('--proxy-port=')) {
      final parsed = int.tryParse(arg.substring('--proxy-port='.length));
      if (parsed == null) {
        throw HeadlessArgsError('Invalid --proxy-port value in "$arg"');
      }
      proxyPort = parsed;
    }
  }

  if (server == null) {
    throw const HeadlessArgsError('--headless requires --server=host:port');
  }

  final parts = server.split(':');
  if (parts.length != 2) {
    throw HeadlessArgsError('--server must be in the form host:port (got "$server")');
  }
  final host = parts[0];
  final port = int.tryParse(parts[1]);
  if (port == null) {
    throw HeadlessArgsError('Invalid port in --server=$server');
  }

  return HeadlessArgs(host: host, port: port, name: name, proxyPort: proxyPort);
}

/// Runs the relay for a single server directly on the core layer, with no
/// Flutter UI. Logs to stdout and runs until SIGINT (Ctrl+C), then tears
/// down cleanly.
Future<void> runHeadless(HeadlessArgs args) async {
  final server = ServerConfig.create(
    name: args.name,
    host: args.host,
    port: args.port,
    proxyPort: args.proxyPort,
  );

  final service = RelayService(onLog: print);

  final completer = Completer<void>();
  final sigintSub = ProcessSignal.sigint.watch().listen((_) {
    if (!completer.isCompleted) completer.complete();
  });

  print(
    'Gazoo headless: advertising "${args.name}" (${args.host}:${args.port}) '
    'on proxy port ${args.proxyPort}. Press Ctrl+C to stop.',
  );
  await service.start([server]);

  await completer.future;
  await sigintSub.cancel();
  print('Stopping...');
  await service.dispose();
  print('Stopped.');
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/cli/headless_runner_test.dart
```

Expected: PASS — all 8 tests green.

- [ ] **Step 5: Wire `--headless` into `main.dart`**

Modify `lib/main.dart`. Add the import at the top (alongside the other imports):

```dart
import 'cli/headless_runner.dart';
```

Change the `main()` signature and add the headless check as the very first thing it does, before `WidgetsFlutterBinding.ensureInitialized()`:

```dart
Future<void> main(List<String> args) async {
  HeadlessArgs? headlessArgs;
  try {
    headlessArgs = parseHeadlessArgs(args);
  } on HeadlessArgsError catch (e) {
    stderr.writeln(e.message);
    exit(64);
  }
  if (headlessArgs != null) {
    await runHeadless(headlessArgs);
    return;
  }

  WidgetsFlutterBinding.ensureInitialized();
  ...
```

(Keep everything after `WidgetsFlutterBinding.ensureInitialized();` exactly as it already is — only the function signature and the new headless-check block above it change.) Add `import 'dart:io';` to `main.dart`'s imports if it isn't already present (needed for `stderr`/`exit`).

- [ ] **Step 6: Run the full suite**

```bash
flutter analyze
flutter test
```

Expected: analyze clean, full suite green (all prior tests plus this task's 8 new ones).

- [ ] **Step 7: Manually verify the headless flag works end to end**

```bash
flutter build macos
./build/macos/Build/Products/Release/gazoo.app/Contents/MacOS/gazoo --headless --server=127.0.0.1:19132 &
sleep 2
kill -INT %1
wait
```

Expected: prints the "Gazoo headless: advertising..." line, then after the `kill -INT` prints "Stopping..." and "Stopped." and exits cleanly (no hang, no crash).

- [ ] **Step 8: Commit**

```bash
git add lib/cli/headless_runner.dart test/cli/headless_runner_test.dart lib/main.dart
git commit -m "Add headless CLI mode: --headless --server=host:port"
```

---

## Self-Review Notes

- **Spec coverage:** All 6 scoped items covered — iOS permission ✓, race fix ✓, error messages ✓, idle-timeout range ✓, pulse animation ✓, headless CLI ✓. Android/iOS platform glue and desktop firewall auto-detection remain explicitly out of scope per the design spec.
- **Type consistency:** `HeadlessArgs`/`HeadlessArgsError` signatures match between Task 6's implementation and its test and `main.dart`'s usage. `_friendlyStartError` is private to `active_relay_screen.dart`, matching how it's only used within that file's own `catchError`.
- **No placeholders:** all code blocks are complete and runnable.

---

**Plan complete and saved to `docs/superpowers/plans/2026-07-12-polish-and-cli.md`.**
