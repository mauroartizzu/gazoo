import 'dart:io';

import 'package:flutter/services.dart';

/// Hooks invoked around the relay lifecycle so platforms can keep the
/// process alive while a relay runs.
///
/// On Android this starts/stops a foreground service (persistent
/// notification) and holds a Wi-Fi multicast lock so the console's LAN
/// discovery broadcasts keep being delivered while the app is backgrounded.
/// Everywhere else the hooks are no-ops.
abstract class RelayPlatform {
  Future<void> onRelayStarted(String serverName);
  Future<void> onRelayStopped();

  /// Picks the right implementation for the current platform.
  factory RelayPlatform.forCurrentPlatform() {
    if (Platform.isAndroid) return AndroidRelayPlatform();
    return NoopRelayPlatform();
  }
}

class NoopRelayPlatform implements RelayPlatform {
  @override
  Future<void> onRelayStarted(String serverName) async {}

  @override
  Future<void> onRelayStopped() async {}
}

class AndroidRelayPlatform implements RelayPlatform {
  static const _channel = MethodChannel('gazoo/relay_platform');

  @override
  Future<void> onRelayStarted(String serverName) async {
    await _channel.invokeMethod<void>(
      'startForegroundService',
      {'serverName': serverName},
    );
  }

  @override
  Future<void> onRelayStopped() async {
    await _channel.invokeMethod<void>('stopForegroundService');
  }
}
