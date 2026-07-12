import 'dart:async';
import 'dart:io';

import '../config/server_config.dart';
import '../discovery/lan_broadcast_responder.dart';
import '../discovery/server_prober.dart';
import 'relay_listener.dart';

enum RelayStatus { listening, consoleConnected }

class RelayEvent {
  final String serverId;
  final RelayStatus status;
  final int bytesIn;
  final int bytesOut;

  const RelayEvent({
    required this.serverId,
    required this.status,
    required this.bytesIn,
    required this.bytesOut,
  });
}

abstract class RelayServiceHandle {
  Stream<RelayEvent> get events;
  Future<void> start(List<ServerConfig> servers);
  Future<void> stop();
  Future<void> dispose();
}

class RelayService implements RelayServiceHandle {
  final Duration idleTimeout;
  final Duration statusPollInterval;
  final ServerProber prober;
  final void Function(String message)? onLog;

  final Map<String, RelayListener> _listeners = {};
  final Map<String, ServerLiveInfo> _lastKnownLiveInfo = {};
  LanBroadcastResponder? _responder;
  List<ServerConfig> _activeServers = [];
  // sync: true is safe here — add() is only ever called from already-async code
  // (after real I/O), and no listener re-enters add() on this controller.
  final StreamController<RelayEvent> _eventController =
      StreamController<RelayEvent>.broadcast(sync: true);
  Timer? _pollTimer;

  RelayService({
    this.idleTimeout = const Duration(seconds: 60),
    this.statusPollInterval = const Duration(seconds: 5),
    ServerProber? prober,
    this.onLog,
  }) : prober = prober ?? const ServerProber();

  Stream<RelayEvent> get events => _eventController.stream;

  Future<void> start(List<ServerConfig> servers) async {
    if (_responder != null) {
      throw StateError('RelayService already running; call stop() first');
    }
    _activeServers = servers;

    try {
      for (final server in servers) {
        final remoteAddresses = await InternetAddress.lookup(
          server.host,
          type: InternetAddressType.IPv4,
        );
        final listener = RelayListener(
          bindAddress: InternetAddress.anyIPv4,
          listenPort: server.proxyPort,
          remoteAddress: remoteAddresses.first,
          remotePort: server.port,
          idleTimeout: idleTimeout,
          onLog: onLog,
        );
        await listener.start();
        _listeners[server.id] = listener;
      }

      _responder = LanBroadcastResponder(
        bindAddress: InternetAddress.anyIPv4,
        enabledServers: () => _activeServers,
        liveInfo: (server) =>
            _lastKnownLiveInfo[server.id] ??
            const ServerLiveInfo(
                protocolVersion: 0, gameVersion: 'unknown', playerCount: 0, maxPlayers: 0),
        onLog: onLog,
      );
      await _responder!.start();
    } catch (_) {
      for (final listener in _listeners.values) {
        await listener.stop();
      }
      _listeners.clear();
      _activeServers = [];
      _responder = null;
      rethrow;
    }

    _pollTimer = Timer.periodic(statusPollInterval, (_) {
      pollNow().catchError((Object error) {
        onLog?.call('pollNow() failed: $error');
      });
    });
    await pollNow();
  }

  Future<void> pollNow() async {
    for (final server in _activeServers) {
      final status = await prober.probe(server.host, server.port);
      if (status.online && status.motd != null) {
        _lastKnownLiveInfo[server.id] = ServerLiveInfo(
          protocolVersion: status.motd!.protocolVersion,
          gameVersion: status.motd!.gameVersion,
          playerCount: status.motd!.playerCount,
          maxPlayers: status.motd!.maxPlayers,
        );
      }
      final listener = _listeners[server.id];
      final activeSessions = listener?.activeSessionCount ?? 0;
      _eventController.add(RelayEvent(
        serverId: server.id,
        status: activeSessions > 0 ? RelayStatus.consoleConnected : RelayStatus.listening,
        bytesIn: listener?.bytesIn ?? 0,
        bytesOut: listener?.bytesOut ?? 0,
      ));
    }
  }

  Future<void> stop() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    await _responder?.stop();
    _responder = null;
    for (final listener in _listeners.values) {
      await listener.stop();
    }
    _listeners.clear();
    _activeServers = [];
  }

  Future<void> dispose() async {
    await stop();
    await _eventController.close();
  }
}
