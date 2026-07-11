import 'dart:async';
import 'dart:io';
import 'package:test/test.dart';
import 'package:gazoo/core/config/server_config.dart';
import 'package:gazoo/core/discovery/server_prober.dart';
import 'package:gazoo/core/raknet/ping_pong_codec.dart';
import 'package:gazoo/core/relay/relay_service.dart';

/// A fake real Minecraft server: answers pings with a valid pong and echoes
/// any other traffic back to whoever sent it (standing in for game traffic).
class _FakeRemoteServer {
  late RawDatagramSocket _socket;
  int get port => _socket.port;

  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    _socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = _socket.receive();
      if (datagram == null) return;
      try {
        final ping = decodeUnconnectedPing(datagram.data);
        final motd = buildMotd(
          serverName: 'Real Server', protocolVersion: 622, gameVersion: '1.21.0',
          playerCount: 2, maxPlayers: 10, serverGuid: 42, worldName: 'World',
          gamemode: 'Survival', portIpv4: port, portIpv6: port,
        );
        _socket.send(
          encodeUnconnectedPong(UnconnectedPong(pingTime: ping.pingTime, serverGuid: 42, motd: motd)),
          datagram.address, datagram.port,
        );
      } on MalformedPacketException {
        _socket.send(datagram.data, datagram.address, datagram.port); // echo game traffic
      }
    });
  }

  void close() => _socket.close();
}

Future<int> _freePort() async {
  final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  final port = s.port;
  s.close();
  return port;
}

void main() {
  late _FakeRemoteServer fakeRemote;
  late RelayService service;

  setUp(() async {
    fakeRemote = _FakeRemoteServer();
    await fakeRemote.start();
  });

  tearDown(() async {
    await service.dispose();
    fakeRemote.close();
  });

  test('start() opens a listener per server and pollNow() reports live info from the real server', () async {
    final proxyPort = await _freePort();
    final server = ServerConfig.create(
      name: 'Test Server', host: '127.0.0.1', port: fakeRemote.port, proxyPort: proxyPort,
    );

    service = RelayService(prober: const ServerProber(timeout: Duration(seconds: 2)));

    final events = <RelayEvent>[];
    final sub = service.events.listen(events.add);
    addTearDown(sub.cancel);

    await service.start([server]);
    await service.pollNow();

    expect(events, isNotEmpty);
    final event = events.firstWhere((e) => e.serverId == server.id);
    expect(event.status, RelayStatus.listening);
  });

  test('an active console session flips status to consoleConnected on the next poll', () async {
    final proxyPort = await _freePort();
    final server = ServerConfig.create(
      name: 'Test Server', host: '127.0.0.1', port: fakeRemote.port, proxyPort: proxyPort,
    );

    service = RelayService(prober: const ServerProber(timeout: Duration(seconds: 2)));
    final events = <RelayEvent>[];
    final sub = service.events.listen(events.add);
    addTearDown(sub.cancel);

    await service.start([server]);

    final console = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(console.close);
    console.send('hello'.codeUnits, InternetAddress.loopbackIPv4, proxyPort);
    await Future.delayed(const Duration(milliseconds: 100));

    await service.pollNow();

    final event = events.lastWhere((e) => e.serverId == server.id);
    expect(event.status, RelayStatus.consoleConnected);
    expect(event.bytesOut, greaterThan(0));
  });

  test('stop() releases the ports so they can be rebound immediately', () async {
    final proxyPort = await _freePort();
    final server = ServerConfig.create(
      name: 'Test Server', host: '127.0.0.1', port: fakeRemote.port, proxyPort: proxyPort,
    );

    service = RelayService(prober: const ServerProber(timeout: Duration(seconds: 2)));
    await service.start([server]);
    await service.stop();

    final rebound = await RawDatagramSocket.bind(InternetAddress.anyIPv4, proxyPort);
    rebound.close();
  });
}
