import 'dart:async';
import 'dart:io';

import 'session.dart';
import 'session_table.dart';

class RelayListener {
  final InternetAddress bindAddress;
  final int listenPort;
  final InternetAddress remoteAddress;
  final int remotePort;
  final Duration idleTimeout;
  final Duration sweepInterval;
  final void Function(String message)? onLog;

  RawDatagramSocket? _socket;
  final SessionTable _sessions = SessionTable();
  final Map<String, Future<RelaySession>> _pending = {};
  Timer? _sweepTimer;
  bool _stopped = false;
  int bytesIn = 0;
  int bytesOut = 0;

  RelayListener({
    required this.bindAddress,
    required this.listenPort,
    required this.remoteAddress,
    required this.remotePort,
    this.idleTimeout = const Duration(seconds: 60),
    this.sweepInterval = const Duration(seconds: 10),
    this.onLog,
  });

  int get boundPort => _socket!.port;
  int get activeSessionCount => _sessions.length;

  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(bindAddress, listenPort);
    _socket!.listen(_onClientEvent);
    _sweepTimer = Timer.periodic(sweepInterval, (_) {
      final expired = _sessions.sweepExpired(idleTimeout, DateTime.now());
      for (final session in expired) {
        onLog?.call('Session expired: ${session.key}');
      }
    });
  }

  void _onClientEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket!.receive();
    if (datagram == null) return;
    unawaited(_handleClientDatagram(datagram));
  }

  Future<void> _handleClientDatagram(Datagram datagram) async {
    if (_stopped) return;
    final key = sessionKeyFor(datagram.address, datagram.port);
    var session = _sessions.get(key);
    if (session == null) {
      final pending = _pending[key];
      try {
        if (pending != null) {
          session = await pending;
        } else {
          final future = _createSession(key, datagram.address, datagram.port);
          _pending[key] = future;
          try {
            session = await future;
          } finally {
            _pending.remove(key);
          }
        }
      } on StateError {
        return;
      }
    }
    if (_stopped || _socket == null) return;
    session.touch(DateTime.now());
    session.serverSocket.send(datagram.data, remoteAddress, remotePort);
    bytesOut += datagram.data.length;
  }

  Future<RelaySession> _createSession(
      String key, InternetAddress clientAddress, int clientPort) async {
    final rawSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    if (_stopped) {
      rawSocket.close();
      throw StateError('RelayListener stopped while creating session for $key');
    }
    final session = RelaySession(
      key: key,
      clientAddress: clientAddress,
      clientPort: clientPort,
      serverSocket: rawSocket,
      lastActivity: DateTime.now(),
    );
    rawSocket.listen((event) => _onServerEvent(event, session));
    _sessions.put(session);
    onLog?.call('New session: $key');
    return session;
  }

  void _onServerEvent(RawSocketEvent event, RelaySession session) {
    if (event != RawSocketEvent.read) return;
    final datagram = session.serverSocket.receive();
    if (datagram == null) return;
    if (_socket == null) return;
    session.touch(DateTime.now());
    _socket!.send(datagram.data, session.clientAddress, session.clientPort);
    bytesIn += datagram.data.length;
  }

  Future<void> stop() async {
    _stopped = true;
    _sweepTimer?.cancel();
    _sweepTimer = null;
    _sessions.closeAll();
    _socket?.close();
    _socket = null;
  }
}
