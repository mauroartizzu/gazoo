import 'dart:async';
import 'dart:io';
import 'package:test/test.dart';
import 'package:gazoo/core/config/server_config.dart';
import 'package:gazoo/core/discovery/lan_broadcast_responder.dart';
import 'package:gazoo/core/raknet/ping_pong_codec.dart';

void main() {
  test('replies with one distinct pong per enabled server, each on its own proxy port', () async {
    final serverA = ServerConfig.create(name: 'Server A', host: 'a.example.com', port: 19132, proxyPort: 19140);
    final serverB = ServerConfig.create(name: 'Server B', host: 'b.example.com', port: 19132, proxyPort: 19141);

    final responder = LanBroadcastResponder(
      bindAddress: InternetAddress.loopbackIPv4,
      listenPort: 0,
      enabledServers: () => [serverA, serverB],
      liveInfo: (server) => const ServerLiveInfo(
        protocolVersion: 622,
        gameVersion: '1.21.0',
        playerCount: 1,
        maxPlayers: 10,
      ),
    );
    await responder.start();
    addTearDown(responder.stop);

    final console = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(console.close);

    final pongs = <UnconnectedPong>[];
    final done = Completer<void>();
    console.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = console.receive();
      if (datagram == null) return;
      pongs.add(decodeUnconnectedPong(datagram.data));
      if (pongs.length == 2 && !done.isCompleted) done.complete();
    });

    const sentPingTime = 123456789;
    console.send(
      encodeUnconnectedPing(const UnconnectedPing(pingTime: sentPingTime, clientGuid: 1)),
      InternetAddress.loopbackIPv4,
      responder.boundPort,
    );

    await done.future.timeout(const Duration(seconds: 2));

    expect(pongs.length, 2);
    for (final pong in pongs) {
      expect(pong.pingTime, sentPingTime);
    }
    final guids = pongs.map((p) => p.serverGuid).toSet();
    expect(guids, {serverA.serverGuid, serverB.serverGuid});

    final motdA = parseMotd(pongs.firstWhere((p) => p.serverGuid == serverA.serverGuid).motd);
    final motdB = parseMotd(pongs.firstWhere((p) => p.serverGuid == serverB.serverGuid).motd);
    expect(motdA.serverName, 'Server A');
    expect(motdA.portIpv4, 19140);
    expect(motdB.serverName, 'Server B');
    expect(motdB.portIpv4, 19141);
    expect(motdA.playerCount, 1);
    expect(motdA.maxPlayers, 10);
    expect(motdA.gameVersion, '1.21.0');
  });

  test('ignores malformed packets instead of crashing', () async {
    final responder = LanBroadcastResponder(
      bindAddress: InternetAddress.loopbackIPv4,
      listenPort: 0,
      enabledServers: () => [],
      liveInfo: (server) => const ServerLiveInfo(
          protocolVersion: 1, gameVersion: '1', playerCount: 0, maxPlayers: 0),
    );
    await responder.start();
    addTearDown(responder.stop);

    final sender = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(sender.close);
    sender.send([0x01, 0x02, 0x03], InternetAddress.loopbackIPv4, responder.boundPort);

    // Give the responder a moment to process; it must not throw or crash the isolate.
    await Future.delayed(const Duration(milliseconds: 100));
    expect(true, isTrue); // reaching here means no uncaught exception occurred
  });
}
