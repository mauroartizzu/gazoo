import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/config/server_config.dart';
import '../../core/relay/relay_service.dart';
import '../../platform/relay_platform.dart';

class RelayNotifier extends ChangeNotifier {
  final RelayServiceHandle Function() createRelayService;
  final void Function(ServerConfig server)? onStart;
  final RelayPlatform relayPlatform;

  RelayServiceHandle? _service;
  StreamSubscription<RelayEvent>? _subscription;
  ServerConfig? _activeServer;
  RelayEvent? _lastEvent;
  Future<void>? _stopping;

  RelayNotifier({
    RelayServiceHandle Function()? createRelayService,
    this.onStart,
    RelayPlatform? relayPlatform,
  })  : createRelayService = createRelayService ?? (() => RelayService()),
        relayPlatform = relayPlatform ?? NoopRelayPlatform();

  ServerConfig? get activeServer => _activeServer;
  RelayEvent? get lastEvent => _lastEvent;
  bool get isRunning => _service != null;

  Future<void> start(ServerConfig server) async {
    if (_stopping != null) {
      await _stopping;
    }
    if (_service != null) {
      throw StateError('RelayNotifier already running; call stop() first');
    }
    final service = createRelayService();
    _service = service;
    _activeServer = server;
    _lastEvent = null;
    _subscription = service.events.listen((event) {
      _lastEvent = event;
      notifyListeners();
    });
    notifyListeners();
    try {
      await service.start([server]);
    } catch (_) {
      await _stopInternal(service);
      rethrow;
    }
    onStart?.call(server);
    try {
      await relayPlatform.onRelayStarted(server.name);
    } catch (_) {
      // A platform-side failure (e.g. the foreground service not starting)
      // must not tear down an otherwise working relay.
    }
  }

  Future<void> stop() async {
    if (_stopping != null) return _stopping;
    final service = _service;
    if (service == null) return;
    final future = _stopInternal(service);
    _stopping = future;
    try {
      await future;
    } finally {
      _stopping = null;
    }
  }

  Future<void> _stopInternal(RelayServiceHandle service) async {
    await _subscription?.cancel();
    _subscription = null;
    await service.dispose();
    _service = null;
    _activeServer = null;
    _lastEvent = null;
    try {
      await relayPlatform.onRelayStopped();
    } catch (_) {
      // Best-effort: failing to stop the notification/service must not
      // block relay teardown.
    }
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
