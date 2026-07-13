// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import '../core/config/server_config.dart';
import '../core/relay/relay_service.dart';

class HeadlessArgsError implements Exception {
  final String message;
  const HeadlessArgsError(this.message);

  @override
  String toString() => message;
}

class HeadlessArgs {
  final String host;
  final int port;
  final String name;
  final int proxyPort;

  const HeadlessArgs({
    required this.host,
    required this.port,
    this.name = 'Gazoo Server',
    this.proxyPort = 19133,
  });
}

/// Parses `--headless --server=host:port [--name=...] [--proxy-port=...]`.
/// Returns null if `--headless` is not present (caller should fall back to
/// the normal GUI). Throws [HeadlessArgsError] on malformed headless args —
/// never calls `exit()`, so this function stays unit-testable.
HeadlessArgs? parseHeadlessArgs(List<String> args) {
  if (!args.contains('--headless')) return null;

  String? server;
  var name = 'Gazoo Server';
  var proxyPort = 19133;

  for (final arg in args) {
    if (arg.startsWith('--server=')) {
      server = arg.substring('--server='.length);
    } else if (arg.startsWith('--name=')) {
      name = arg.substring('--name='.length);
    } else if (arg.startsWith('--proxy-port=')) {
      final parsed = int.tryParse(arg.substring('--proxy-port='.length));
      if (parsed == null) {
        throw HeadlessArgsError('Invalid --proxy-port value in "$arg"');
      }
      proxyPort = parsed;
    }
  }

  if (server == null) {
    throw const HeadlessArgsError('--headless requires --server=host:port');
  }

  final parts = server.split(':');
  if (parts.length != 2) {
    throw HeadlessArgsError('--server must be in the form host:port (got "$server")');
  }
  final host = parts[0];
  final port = int.tryParse(parts[1]);
  if (port == null) {
    throw HeadlessArgsError('Invalid port in --server=$server');
  }
  if (port < 1 || port > 65535) {
    throw HeadlessArgsError('Port must be between 1 and 65535 (got $port)');
  }
  if (proxyPort < 1 || proxyPort > 65535) {
    throw HeadlessArgsError('--proxy-port must be between 1 and 65535 (got $proxyPort)');
  }
  if (proxyPort == 19132) {
    throw const HeadlessArgsError('19132 is reserved for discovery; choose a different --proxy-port');
  }

  return HeadlessArgs(host: host, port: port, name: name, proxyPort: proxyPort);
}

/// Runs the relay for a single server directly on the core layer, with no
/// Flutter UI. Logs to stdout and runs until SIGINT (Ctrl+C), then tears
/// down cleanly.
Future<void> runHeadless(HeadlessArgs args) async {
  final server = ServerConfig.create(
    name: args.name,
    host: args.host,
    port: args.port,
    proxyPort: args.proxyPort,
  );

  final service = RelayService(onLog: print);

  final completer = Completer<void>();
  final sigintSub = ProcessSignal.sigint.watch().listen((_) {
    if (!completer.isCompleted) completer.complete();
  });

  print(
    'Gazoo headless: advertising "${args.name}" (${args.host}:${args.port}) '
    'on proxy port ${args.proxyPort}. Press Ctrl+C to stop.',
  );
  await service.start([server]);

  await completer.future;
  await sigintSub.cancel();
  print('Stopping...');
  await service.dispose();
  print('Stopped.');
}
