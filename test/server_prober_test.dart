import 'dart:io';
import 'package:test/test.dart';
import 'package:gazoo/core/discovery/server_prober.dart';
import 'package:gazoo/core/raknet/ping_pong_codec.dart';

/// A fake real Minecraft server that answers Unconnected Ping with a valid Pong.
class _FakeMinecraftServer {
  late RawDatagramSocket _socket;
  int get port => _socket.port;

  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    _socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = _socket.receive();
      if (datagram == null) return;
      final ping = decodeUnconnectedPing(datagram.data);
      final motd = buildMotd(
        serverName: 'Fake Server',
        protocolVersion: 622,
        gameVersion: '1.21.0',
        playerCount: 4,
        maxPlayers: 20,
        serverGuid: 777,
        worldName: 'World',
        gamemode: 'Survival',
        portIpv4: port,
        portIpv6: port,
      );
      final pong = UnconnectedPong(pingTime: ping.pingTime, serverGuid: 777, motd: motd);
      _socket.send(encodeUnconnectedPong(pong), datagram.address, datagram.port);
    });
  }

  void close() => _socket.close();
}

void main() {
  test('probe returns online status with parsed live server info', () async {
    final fakeServer = _FakeMinecraftServer();
    await fakeServer.start();
    addTearDown(fakeServer.close);

    const prober = ServerProber(timeout: Duration(seconds: 2));
    final status = await prober.probe('127.0.0.1', fakeServer.port);

    expect(status.online, isTrue);
    expect(status.motd!.serverName, 'Fake Server');
    expect(status.motd!.protocolVersion, 622);
    expect(status.motd!.gameVersion, '1.21.0');
    expect(status.motd!.playerCount, 4);
    expect(status.motd!.maxPlayers, 20);
    expect(status.latency, isNotNull);
  });

  test('probe returns offline status when nothing responds before the timeout', () async {
    // Bind then immediately close, so the port is (almost certainly) unused
    // and nothing will reply within the short test timeout.
    final probe = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final unusedPort = probe.port;
    probe.close();

    const prober = ServerProber(timeout: Duration(milliseconds: 300));
    final status = await prober.probe('127.0.0.1', unusedPort);

    expect(status.online, isFalse);
    expect(status.error, isNotNull);
  });

  test('onLog receives a probing message and an online message on success', () async {
    final fakeServer = _FakeMinecraftServer();
    await fakeServer.start();
    addTearDown(fakeServer.close);

    final logged = <String>[];
    final prober = ServerProber(timeout: const Duration(seconds: 2), onLog: logged.add);
    final status = await prober.probe('127.0.0.1', fakeServer.port);

    expect(status.online, isTrue);
    expect(logged, isNotEmpty);
    expect(logged.any((m) => m.contains('Probing') && m.contains('127.0.0.1')), isTrue);
    expect(logged.any((m) => m.contains('is online') && m.contains('4/20')), isTrue);
  });

  test('onLog receives a probing message and a timeout message when nothing responds', () async {
    final probe = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final unusedPort = probe.port;
    probe.close();

    final logged = <String>[];
    final prober = ServerProber(timeout: const Duration(milliseconds: 300), onLog: logged.add);
    final status = await prober.probe('127.0.0.1', unusedPort);

    expect(status.online, isFalse);
    expect(logged, isNotEmpty);
    expect(logged.any((m) => m.contains('Probing') && m.contains('127.0.0.1')), isTrue);
    expect(logged.any((m) => m.contains('did not respond')), isTrue);
  });
}
