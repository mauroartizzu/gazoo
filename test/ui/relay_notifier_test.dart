import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:gazoo/core/config/server_config.dart';
import 'package:gazoo/core/relay/relay_service.dart';
import 'package:gazoo/ui/state/relay_notifier.dart';

class _FakeRelayService implements RelayServiceHandle {
  final _controller = StreamController<RelayEvent>.broadcast(sync: true);
  bool started = false;
  bool disposed = false;
  List<ServerConfig>? startedWith;

  @override
  Stream<RelayEvent> get events => _controller.stream;

  @override
  Future<void> start(List<ServerConfig> servers) async {
    started = true;
    startedWith = servers;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    disposed = true;
    await _controller.close();
  }

  void emit(RelayEvent event) => _controller.add(event);
}

void main() {
  ServerConfig sampleServer() => ServerConfig.create(
        name: 'Test', host: 'example.com', port: 19132, proxyPort: 19133,
      );

  test('start calls the fake service.start with the given server and notifies', () async {
    final fake = _FakeRelayService();
    final notifier = RelayNotifier(createRelayService: () => fake);
    var notified = 0;
    notifier.addListener(() => notified++);

    final server = sampleServer();
    await notifier.start(server);

    expect(fake.started, isTrue);
    expect(fake.startedWith, [server]);
    expect(notifier.activeServer, server);
    expect(notifier.isRunning, isTrue);
    expect(notified, greaterThan(0));
  });

  test('events from the service are forwarded as lastEvent and trigger notifyListeners', () async {
    final fake = _FakeRelayService();
    final notifier = RelayNotifier(createRelayService: () => fake);
    await notifier.start(sampleServer());

    var notified = 0;
    notifier.addListener(() => notified++);

    const event = RelayEvent(
      serverId: 'abc', status: RelayStatus.consoleConnected, bytesIn: 10, bytesOut: 20,
    );
    fake.emit(event);

    expect(notifier.lastEvent, event);
    expect(notified, 1);
  });

  test('stop tears down the service and resets state', () async {
    final fake = _FakeRelayService();
    final notifier = RelayNotifier(createRelayService: () => fake);
    await notifier.start(sampleServer());

    await notifier.stop();

    expect(fake.disposed, isTrue);
    expect(notifier.isRunning, isFalse);
    expect(notifier.activeServer, isNull);
    expect(notifier.lastEvent, isNull);
  });

  test('start throws if already running', () async {
    final fake = _FakeRelayService();
    final notifier = RelayNotifier(createRelayService: () => fake);
    await notifier.start(sampleServer());

    expect(() => notifier.start(sampleServer()), throwsStateError);
  });

  test('stop is a no-op when nothing is running', () async {
    final notifier = RelayNotifier(createRelayService: () => _FakeRelayService());
    await notifier.stop();
    expect(notifier.isRunning, isFalse);
  });
}
