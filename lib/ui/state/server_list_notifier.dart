import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/server_config.dart';
import '../../core/discovery/server_prober.dart';

class ServerListNotifier extends ChangeNotifier {
  static const _prefsKey = 'saved_servers';

  final SharedPreferences prefs;
  final Future<ServerStatus> Function(String host, int port) probe;
  final Duration pollInterval;

  List<ServerConfig> _servers = [];
  final Map<String, ServerStatus> _statuses = {};
  Timer? _pollTimer;

  ServerListNotifier({
    required this.prefs,
    Future<ServerStatus> Function(String host, int port)? probe,
    this.pollInterval = const Duration(seconds: 10),
  }) : probe = probe ?? const ServerProber().probe {
    _loadFromPrefs();
  }

  List<ServerConfig> get servers => List.unmodifiable(_servers);

  ServerStatus? statusFor(String id) => _statuses[id];

  void _loadFromPrefs() {
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    final decoded = jsonDecode(raw) as List<dynamic>;
    _servers = decoded.map((e) => ServerConfig.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> _persist() async {
    final encoded = jsonEncode(_servers.map((s) => s.toJson()).toList());
    await prefs.setString(_prefsKey, encoded);
  }

  Future<void> add(ServerConfig server) async {
    _servers = [..._servers, server];
    notifyListeners();
    await _persist();
  }

  Future<void> update(ServerConfig server) async {
    _servers = _servers.map((s) => s.id == server.id ? server : s).toList();
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String id) async {
    _servers = _servers.where((s) => s.id != id).toList();
    _statuses.remove(id);
    notifyListeners();
    await _persist();
  }

  Future<void> pollNow() async {
    for (final server in _servers) {
      _statuses[server.id] = await probe(server.host, server.port);
    }
    notifyListeners();
  }

  void startPolling() {
    _pollTimer?.cancel();
    unawaited(pollNow());
    _pollTimer = Timer.periodic(pollInterval, (_) => pollNow());
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
