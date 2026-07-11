import 'dart:io';

import '../config/server_config.dart';
import '../raknet/ping_pong_codec.dart';

class ServerLiveInfo {
  final int protocolVersion;
  final String gameVersion;
  final int playerCount;
  final int maxPlayers;

  const ServerLiveInfo({
    required this.protocolVersion,
    required this.gameVersion,
    required this.playerCount,
    required this.maxPlayers,
  });
}

class LanBroadcastResponder {
  final InternetAddress bindAddress;
  final int listenPort;
  final List<ServerConfig> Function() enabledServers;
  final ServerLiveInfo Function(ServerConfig server) liveInfo;
  final void Function(String message)? onLog;

  RawDatagramSocket? _socket;

  LanBroadcastResponder({
    required this.bindAddress,
    this.listenPort = 19132,
    required this.enabledServers,
    required this.liveInfo,
    this.onLog,
  });

  int get boundPort => _socket!.port;

  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(bindAddress, listenPort);
    _socket!.broadcastEnabled = true;
    _socket!.listen(_onEvent);
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    if (_socket == null) return;
    final datagram = _socket!.receive();
    if (datagram == null) return;

    final UnconnectedPing ping;
    try {
      ping = decodeUnconnectedPing(datagram.data);
    } on MalformedPacketException {
      return;
    }

    for (final server in enabledServers()) {
      final info = liveInfo(server);
      final motd = buildMotd(
        serverName: server.name,
        protocolVersion: info.protocolVersion,
        gameVersion: info.gameVersion,
        playerCount: info.playerCount,
        maxPlayers: info.maxPlayers,
        serverGuid: server.serverGuid,
        worldName: server.name,
        gamemode: 'Survival',
        portIpv4: server.proxyPort,
        portIpv6: server.proxyPort,
      );
      final pong = UnconnectedPong(
        pingTime: ping.pingTime,
        serverGuid: server.serverGuid,
        motd: motd,
      );
      _socket!.send(encodeUnconnectedPong(pong), datagram.address, datagram.port);
      onLog?.call(
          'Replied to ${datagram.address.address}:${datagram.port} for server "${server.name}"');
    }
  }

  Future<void> stop() async {
    _socket?.close();
    _socket = null;
  }
}
