import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gazoo/core/config/server_config.dart';
import 'package:gazoo/core/discovery/server_prober.dart';
import 'package:gazoo/ui/state/server_list_notifier.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  ServerConfig sampleServer({String name = 'Test'}) => ServerConfig.create(
        name: name,
        host: 'example.com',
        port: 19132,
        proxyPort: 19133,
      );

  test('starts empty when no servers persisted', () {
    final notifier = ServerListNotifier(prefs: prefs);
    expect(notifier.servers, isEmpty);
  });

  test('add persists and notifies listeners; a fresh instance reloads it', () async {
    final notifier = ServerListNotifier(prefs: prefs);
    var notified = 0;
    notifier.addListener(() => notified++);

    final server = sampleServer();
    await notifier.add(server);

    expect(notifier.servers, [server]);
    expect(notified, greaterThan(0));

    final reloaded = ServerListNotifier(prefs: prefs);
    expect(reloaded.servers.single.id, server.id);
    expect(reloaded.servers.single.name, server.name);
  });

  test('update replaces the matching server by id', () async {
    final notifier = ServerListNotifier(prefs: prefs);
    final server = sampleServer();
    await notifier.add(server);

    final updated = server.copyWith(name: 'Renamed');
    await notifier.update(updated);

    expect(notifier.servers.single.name, 'Renamed');
    expect(notifier.servers.single.id, server.id);
  });

  test('remove deletes the server and its cached status', () async {
    final notifier = ServerListNotifier(prefs: prefs);
    final server = sampleServer();
    await notifier.add(server);

    await notifier.remove(server.id);

    expect(notifier.servers, isEmpty);
    expect(notifier.statusFor(server.id), isNull);
  });

  test('pollNow updates statusFor using the injected probe function', () async {
    final notifier = ServerListNotifier(
      prefs: prefs,
      probe: (host, port) async => const ServerStatus.offline('unreachable in test'),
    );
    final server = sampleServer();
    await notifier.add(server);

    await notifier.pollNow();

    expect(notifier.statusFor(server.id)!.online, isFalse);
  });

  test('startPolling calls pollNow immediately and then on an interval', () async {
    var callCount = 0;
    final notifier = ServerListNotifier(
      prefs: prefs,
      pollInterval: const Duration(milliseconds: 30),
      probe: (host, port) async {
        callCount++;
        return const ServerStatus.offline('n/a');
      },
    );
    await notifier.add(sampleServer());

    notifier.startPolling();
    await Future.delayed(const Duration(milliseconds: 100));
    notifier.stopPolling();

    expect(callCount, greaterThanOrEqualTo(2));
  });
}
