import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:gazoo/core/config/server_config.dart';
import 'package:gazoo/core/relay/relay_service.dart';
import 'package:gazoo/ui/screens/active_relay_screen.dart';
import 'package:gazoo/ui/state/relay_notifier.dart';

class _FakeRelayService implements RelayServiceHandle {
  final _controller = StreamController<RelayEvent>.broadcast(sync: true);
  bool stopped = false;

  @override
  Stream<RelayEvent> get events => _controller.stream;

  @override
  Future<void> start(List<ServerConfig> servers) async {}

  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  Future<void> dispose() async {
    stopped = true;
    await _controller.close();
  }

  void emit(RelayEvent event) => _controller.add(event);
}

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

/// Pushes ActiveRelayScreen onto a real navigation stack (rather than making
/// it the app's `home`), so `Navigator.pop()` inside the screen's Stop button
/// has somewhere to pop back to — matching how Task 8 will actually navigate
/// to it.
Widget _harness(RelayNotifier relayNotifier, ServerConfig server) {
  return ChangeNotifierProvider.value(
    value: relayNotifier,
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ActiveRelayScreen(server: server)),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  ServerConfig sampleServer() => ServerConfig.create(
        name: 'Test', host: 'example.com', port: 19132, proxyPort: 19133,
      );

  testWidgets('shows Starting… then Listening once the relay reports it', (tester) async {
    final fake = _FakeRelayService();
    final relayNotifier = RelayNotifier(createRelayService: () => fake);
    final server = sampleServer();

    await tester.pumpWidget(_harness(relayNotifier, server));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Starting…'), findsOneWidget);

    fake.emit(RelayEvent(
      serverId: server.id, status: RelayStatus.listening, bytesIn: 0, bytesOut: 0,
    ));
    await tester.pump();

    expect(find.text('Listening'), findsOneWidget);
  });

  testWidgets('shows Console Connected and byte counters once a session is active', (tester) async {
    final fake = _FakeRelayService();
    final relayNotifier = RelayNotifier(createRelayService: () => fake);
    final server = sampleServer();

    await tester.pumpWidget(_harness(relayNotifier, server));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    fake.emit(RelayEvent(
      serverId: server.id, status: RelayStatus.consoleConnected, bytesIn: 42, bytesOut: 7,
    ));
    await tester.pump();

    expect(find.text('Console Connected'), findsOneWidget);
    expect(find.textContaining('42'), findsOneWidget);
    expect(find.textContaining('7'), findsOneWidget);
  });

  testWidgets('Stop Relay button stops the relay and pops the screen', (tester) async {
    final fake = _FakeRelayService();
    final relayNotifier = RelayNotifier(createRelayService: () => fake);
    final server = sampleServer();

    await tester.pumpWidget(_harness(relayNotifier, server));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // runAsync bridges to the real event loop: RelayNotifier.stop()'s
    // `await _subscription.cancel()` does not settle under fake-clock pump()
    // alone in this environment. Do not remove — see task-7 investigation.
    await tester.runAsync(() async {
      await tester.tap(find.text('Stop Relay'));
      await tester.pump();
    });
    await tester.pumpAndSettle();

    expect(fake.stopped, isTrue);
    expect(find.text('Active Relay'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('shows a specific message when the port is already in use', (tester) async {
    final relayNotifier = RelayNotifier(
      createRelayService: () => _ThrowingRelayService(
        const SocketException('Address already in use', osError: null),
      ),
    );
    final server = sampleServer();

    await tester.pumpWidget(_harness(relayNotifier, server));
    // runAsync bridges to the real event loop: RelayNotifier.start()'s
    // failure path now does `await _subscription.cancel()` /
    // `await service.dispose()` (see task-2 rollback fix), which does not
    // settle under fake-clock pump() alone in this environment.
    await tester.runAsync(() async {
      await tester.tap(find.text('Open'));
      await tester.pump();
    });
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
    await tester.runAsync(() async {
      await tester.tap(find.text('Open'));
      await tester.pump();
    });
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
    await tester.runAsync(() async {
      await tester.tap(find.text('Open'));
      await tester.pump();
    });
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not find'), findsOneWidget);
  });

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
}
