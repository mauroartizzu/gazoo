import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/server_config.dart';
import '../../core/discovery/server_prober.dart';
import '../state/server_list_notifier.dart';
import 'active_relay_screen.dart';

class ServerListScreen extends StatelessWidget {
  const ServerListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<ServerListNotifier>();
    final servers = notifier.servers;

    return Scaffold(
      appBar: AppBar(title: const Text('Gazoo Servers')),
      body: servers.isEmpty
          ? const Center(child: Text('No servers yet. Tap + to add one.'))
          : ListView.builder(
              itemCount: servers.length,
              itemBuilder: (context, index) {
                final server = servers[index];
                final status = notifier.statusFor(server.id);
                return ListTile(
                  key: ValueKey(server.id),
                  title: Text(server.name),
                  subtitle: Text(_subtitleFor(server, status)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: Key('edit-server-${server.id}'),
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit ${server.name}',
                        onPressed: () => _showServerFormDialog(context, initial: server),
                      ),
                      IconButton(
                        key: Key('delete-server-${server.id}'),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Remove ${server.name}',
                        onPressed: () => notifier.remove(server.id),
                      ),
                    ],
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ActiveRelayScreen(server: server)),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showServerFormDialog(context),
        tooltip: 'Add server',
        child: const Icon(Icons.add),
      ),
    );
  }

  String _subtitleFor(ServerConfig server, ServerStatus? status) {
    final address = '${server.host}:${server.port}';
    if (status == null) return address;
    if (!status.online) return '$address — offline';
    final motd = status.motd;
    if (motd == null) return '$address — online';
    return '$address — ${motd.playerCount}/${motd.maxPlayers} players';
  }

  Future<void> _showServerFormDialog(BuildContext context, {ServerConfig? initial}) async {
    final notifier = context.read<ServerListNotifier>();
    final result = await showDialog<_ServerFormResult>(
      context: context,
      builder: (_) => _ServerFormDialog(initial: initial),
    );
    if (result != null) {
      if (initial == null) {
        await notifier.add(ServerConfig.create(
          name: result.name,
          host: result.host,
          port: result.port,
          proxyPort: result.proxyPort,
        ));
      } else {
        await notifier.update(initial.copyWith(
          name: result.name,
          host: result.host,
          port: result.port,
          proxyPort: result.proxyPort,
        ));
      }
    }
  }
}

class _ServerFormResult {
  final String name;
  final String host;
  final int port;
  final int proxyPort;

  const _ServerFormResult({
    required this.name,
    required this.host,
    required this.port,
    required this.proxyPort,
  });
}

class _ServerFormDialog extends StatefulWidget {
  final ServerConfig? initial;

  const _ServerFormDialog({this.initial});

  @override
  State<_ServerFormDialog> createState() => _ServerFormDialogState();
}

class _ServerFormDialogState extends State<_ServerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '19132');
  final _proxyPortController = TextEditingController(text: '19133');

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _nameController.text = initial.name;
      _hostController.text = initial.host;
      _portController.text = initial.port.toString();
      _proxyPortController.text = initial.proxyPort.toString();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _proxyPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add server' : 'Edit server'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('server-name-field'),
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Server name'),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            TextFormField(
              key: const Key('server-host-field'),
              controller: _hostController,
              decoration: const InputDecoration(labelText: 'Host / IP address'),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            TextFormField(
              key: const Key('server-port-field'),
              controller: _portController,
              decoration: const InputDecoration(labelText: 'Port'),
              keyboardType: TextInputType.number,
              validator: _validatePort,
            ),
            TextFormField(
              key: const Key('server-proxy-port-field'),
              controller: _proxyPortController,
              decoration: const InputDecoration(labelText: 'Local proxy port'),
              keyboardType: TextInputType.number,
              validator: _validatePort,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('server-form-save-button'),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop(_ServerFormResult(
                name: _nameController.text,
                host: _hostController.text,
                port: int.parse(_portController.text),
                proxyPort: int.parse(_proxyPortController.text),
              ));
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  String? _validatePort(String? value) {
    if (value == null || value.isEmpty) return 'Required';
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 1 || parsed > 65535) return 'Invalid port';
    return null;
  }
}
