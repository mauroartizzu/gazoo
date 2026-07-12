import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_log.dart';
import '../state/settings_notifier.dart';
import 'onboarding_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<SettingsNotifier>();
    final settings = notifier.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Idle timeout'),
            subtitle: Text('${settings.idleTimeout.inSeconds} seconds'),
            trailing: DropdownButton<int>(
              key: const Key('idle-timeout-dropdown'),
              value: settings.idleTimeout.inSeconds,
              items: const [30, 60, 120, 300]
                  .map((seconds) => DropdownMenuItem(value: seconds, child: Text('${seconds}s')))
                  .toList(),
              onChanged: (seconds) {
                if (seconds != null) {
                  context.read<SettingsNotifier>().update(
                        (s) => s.copyWith(idleTimeout: Duration(seconds: seconds)),
                      );
                }
              },
            ),
          ),
          SwitchListTile(
            key: const Key('auto-start-switch'),
            title: const Text('Auto-start last used server'),
            value: settings.autoStartLastServer,
            onChanged: (value) => context.read<SettingsNotifier>().update(
                  (s) => s.copyWith(autoStartLastServer: value),
                ),
          ),
          SwitchListTile(
            key: const Key('dark-mode-switch'),
            title: const Text('Dark theme'),
            value: settings.darkMode,
            onChanged: (value) => context.read<SettingsNotifier>().update(
                  (s) => s.copyWith(darkMode: value),
                ),
          ),
          SwitchListTile(
            key: const Key('log-panel-switch'),
            title: const Text('Show log panel'),
            value: settings.verboseLogging,
            onChanged: (value) => context.read<SettingsNotifier>().update(
                  (s) => s.copyWith(verboseLogging: value),
                ),
          ),
          if (settings.verboseLogging) const _LogPanel(),
          ListTile(
            title: const Text('Help'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OnboardingScreen(showGetStarted: false)),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogPanel extends StatelessWidget {
  const _LogPanel();

  @override
  Widget build(BuildContext context) {
    final log = context.watch<AppLog>();
    return ExpansionTile(
      key: const Key('log-panel'),
      title: const Text('Log'),
      initiallyExpanded: true,
      children: [
        SizedBox(
          height: 150,
          child: ListView(
            children:
                log.lines.map((line) => Text(line, style: const TextStyle(fontSize: 11))).toList(),
          ),
        ),
      ],
    );
  }
}
