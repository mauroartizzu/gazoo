import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/config/server_config.dart';
import '../../core/relay/relay_service.dart';

class RelayNotifier extends ChangeNotifier {
  final RelayServiceHandle Function() createRelayService;
  final void Function(ServerConfig server)? onStart;

  RelayServiceHandle? _service;
  StreamSubscription<RelayEvent>? _subscription;
  ServerConfig? _activeServer;
  RelayEvent? _lastEvent;

  RelayNotifier({
    RelayServiceHandle Function()? createRelayService,
    this.onStart,
  }) : createRelayService = createRelayService ?? (() => RelayService());

  ServerConfig? get activeServer => _activeServer;
  RelayEvent? get lastEvent => _lastEvent;
  bool get isRunning => _service != null;

  Future<void> start(ServerConfig server) async {
    if (_service != null) {
      throw StateError('RelayNotifier already running; call stop() first');
    }
    final service = createRelayService();
    _service = service;
    _activeServer = server;
    onStart?.call(server);
    _lastEvent = null;
    _subscription = service.events.listen((event) {
      _lastEvent = event;
      notifyListeners();
    });
    notifyListeners();
    await service.start([server]);
  }

  Future<void> stop() async {
    final service = _service;
    if (service == null) return;
    await _subscription?.cancel();
    _subscription = null;
    await service.dispose();
    _service = null;
    _activeServer = null;
    _lastEvent = null;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
