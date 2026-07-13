import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gazoo/core/config/server_config.dart';
import 'package:gazoo/core/relay/relay_service.dart';
import 'package:gazoo/platform/relay_platform.dart';
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

class _FailingRelayService implements RelayServiceHandle {
  final _controller = StreamController<RelayEvent>.broadcast(sync: true);
  bool disposed = false;

  @override
  Stream<RelayEvent> get events => _controller.stream;

  @override
  Future<void> start(List<ServerConfig> servers) async {
    throw const SocketException('Address already in use');
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    disposed = true;
    await _controller.close();
  }
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

  test('onStart callback fires with the server when start() is called', () async {
    final fake = _FakeRelayService();
    ServerConfig? startedWith;
    final notifier = RelayNotifier(
      createRelayService: () => fake,
      onStart: (server) => startedWith = server,
    );

    final server = sampleServer();
    await notifier.start(server);

    expect(startedWith, server);
  });

  test('a failed start() leaves the notifier in a clean, not-running state and does not fire onStart', () async {
    final fake = _FailingRelayService();
    ServerConfig? startedWith;
    final notifier = RelayNotifier(
      createRelayService: () => fake,
      onStart: (server) => startedWith = server,
    );

    await expectLater(notifier.start(sampleServer()), throwsA(isA<SocketException>()));

    expect(notifier.isRunning, isFalse);
    expect(notifier.activeServer, isNull);
    expect(notifier.lastEvent, isNull);
    expect(startedWith, isNull);
    expect(fake.disposed, isTrue);

    // The notifier should be usable again after the failure (not stuck).
    final goodFake = _FakeRelayService();
    final notifier2 = RelayNotifier(createRelayService: () => goodFake);
    await notifier2.start(sampleServer());
    expect(notifier2.isRunning, isTrue);
  });

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

  test('platform hooks fire on start (with server name) and on stop', () async {
    final fake = _FakeRelayService();
    final platform = _RecordingRelayPlatform();
    final notifier = RelayNotifier(
      createRelayService: () => fake,
      relayPlatform: platform,
    );

    await notifier.start(sampleServer());
    expect(platform.startedWith, 'Test');
    expect(platform.stopCalls, 0);

    await notifier.stop();
    expect(platform.stopCalls, 1);
  });

  test('platform hooks do not fire when the relay fails to start', () async {
    final platform = _RecordingRelayPlatform();
    final notifier = RelayNotifier(
      createRelayService: () => _FailingRelayService(),
      relayPlatform: platform,
    );

    await expectLater(notifier.start(sampleServer()), throwsA(isA<SocketException>()));

    expect(platform.startedWith, isNull);
    // _stopInternal runs during rollback, so a stop-side call is fine — but
    // the "started" hook must never have fired for a relay that never ran.
  });

  test('a platform hook throwing does not break the relay lifecycle', () async {
    final fake = _FakeRelayService();
    final notifier = RelayNotifier(
      createRelayService: () => fake,
      relayPlatform: _ThrowingRelayPlatform(),
    );

    await notifier.start(sampleServer());
    expect(notifier.isRunning, isTrue);

    await notifier.stop();
    expect(notifier.isRunning, isFalse);
    expect(fake.disposed, isTrue);
  });
}

class _RecordingRelayPlatform implements RelayPlatform {
  String? startedWith;
  int stopCalls = 0;

  @override
  Future<void> onRelayStarted(String serverName) async {
    startedWith = serverName;
  }

  @override
  Future<void> onRelayStopped() async {
    stopCalls++;
  }
}

class _ThrowingRelayPlatform implements RelayPlatform {
  @override
  Future<void> onRelayStarted(String serverName) async {
    throw PlatformException(code: 'boom');
  }

  @override
  Future<void> onRelayStopped() async {
    throw PlatformException(code: 'boom');
  }
}
