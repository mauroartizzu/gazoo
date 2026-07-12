import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/server_config.dart';
import '../../core/relay/relay_service.dart';
import '../state/relay_notifier.dart';

class ActiveRelayScreen extends StatefulWidget {
  final ServerConfig server;

  const ActiveRelayScreen({super.key, required this.server});

  @override
  State<ActiveRelayScreen> createState() => _ActiveRelayScreenState();
}

class _ActiveRelayScreenState extends State<ActiveRelayScreen> {
  RelayNotifier? _relayNotifier;
  late final Future<List<String>> _lanIpsFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _relayNotifier = context.read<RelayNotifier>();
  }

  @override
  void initState() {
    super.initState();
    _lanIpsFuture = _detectedLanIps();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RelayNotifier>().start(widget.server).catchError((Object error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_friendlyStartError(error))),
          );
        }
      });
    });
  }

  @override
  void dispose() {
    final notifier = _relayNotifier;
    if (notifier != null && notifier.isRunning) {
      notifier.stop();
    }
    super.dispose();
  }

  Future<void> _stopAndPop() async {
    await context.read<RelayNotifier>().stop();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<RelayNotifier>();
    final event = notifier.lastEvent;

    return Scaffold(
      appBar: AppBar(title: const Text('Active Relay')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Server: ${widget.server.name}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_statusLabel(event)),
            const SizedBox(height: 8),
            FutureBuilder<List<String>>(
              future: _lanIpsFuture,
              builder: (context, snapshot) {
                final ips = snapshot.data ?? const [];
                return Text('LAN IP: ${ips.isEmpty ? 'detecting…' : ips.join(', ')}');
              },
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                '↑ ${event?.bytesOut ?? 0} B   ↓ ${event?.bytesIn ?? 0} B',
                key: ValueKey('${event?.bytesOut ?? 0}-${event?.bytesIn ?? 0}'),
              ),
            ),
            const Spacer(),
            if (Platform.isAndroid || Platform.isIOS)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Keep this app open while playing.',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _stopAndPop,
                child: const Text('Stop Relay'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(RelayEvent? event) {
    if (event == null) return 'Starting…';
    switch (event.status) {
      case RelayStatus.consoleConnected:
        return 'Console Connected';
      case RelayStatus.listening:
        return 'Listening';
    }
  }

  Future<List<String>> _detectedLanIps() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      return interfaces.expand((i) => i.addresses).map((a) => a.address).toList();
    } catch (_) {
      return const [];
    }
  }
}

String _friendlyStartError(Object error) {
  if (error is SocketException) {
    final message = error.message.toLowerCase();
    if (message.contains('already in use')) {
      return 'Port already in use — another app (or another Gazoo instance) may already be using this port.';
    }
    if (message.contains('permission denied')) {
      return 'Permission denied opening the network port. Check your firewall settings.';
    }
    if (message.contains('failed host lookup') || message.contains('no address associated')) {
      return 'Could not find the server host. Check the host/IP address.';
    }
    return 'Network error: ${error.message}';
  }
  if (error is StateError) {
    return error.message;
  }
  return 'Failed to start relay: $error';
}
