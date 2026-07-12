import 'dart:async';
import 'dart:io';

import '../raknet/ping_pong_codec.dart';

class ServerStatus {
  final bool online;
  final MotdFields? motd;
  final Duration? latency;
  final String? error;

  const ServerStatus.online(MotdFields this.motd, Duration this.latency)
      : online = true,
        error = null;

  const ServerStatus.offline(String this.error)
      : online = false,
        motd = null,
        latency = null;
}

class ServerProber {
  final Duration timeout;
  final void Function(String message)? onLog;
  const ServerProber({this.timeout = const Duration(seconds: 3), this.onLog});

  Future<ServerStatus> probe(String host, int port) async {
    RawDatagramSocket? socket;
    StreamSubscription? subscription;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final addresses = await InternetAddress.lookup(
        host,
        type: InternetAddressType.IPv4,
      );
      if (addresses.isEmpty) {
        return ServerStatus.offline('Could not resolve host: $host');
      }
      final address = addresses.first;
      final sentAt = DateTime.now();
      final ping = UnconnectedPing(pingTime: sentAt.millisecondsSinceEpoch, clientGuid: 0);
      onLog?.call('Probing $host:$port...');
      socket.send(encodeUnconnectedPing(ping), address, port);

      final completer = Completer<ServerStatus>();
      final timer = Timer(timeout, () {
        if (!completer.isCompleted) {
          onLog?.call('$host:$port did not respond within $timeout');
          completer.complete(ServerStatus.offline('Timed out waiting for response'));
        }
      });

      subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket!.receive();
        if (datagram == null) return;
        try {
          final pong = decodeUnconnectedPong(datagram.data);
          final motd = parseMotd(pong.motd);
          if (!completer.isCompleted) {
            onLog?.call('$host:$port is online (${motd.playerCount}/${motd.maxPlayers} players)');
            completer.complete(ServerStatus.online(motd, DateTime.now().difference(sentAt)));
          }
        } on MalformedPacketException {
          // Not a valid pong (or from an unrelated sender) — keep waiting.
        }
      });

      final result = await completer.future;
      timer.cancel();
      return result;
    } on SocketException catch (e) {
      return ServerStatus.offline(e.message);
    } finally {
      await subscription?.cancel();
      socket?.close();
    }
  }
}
