import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/relay/relay_service.dart';
import 'ui/screens/active_relay_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/server_list_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/state/app_log.dart';
import 'ui/state/relay_notifier.dart';
import 'ui/state/server_list_notifier.dart';
import 'ui/state/settings_notifier.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final appLog = AppLog();
  final serverListNotifier = ServerListNotifier(prefs: prefs)..startPolling();
  final settingsNotifier = SettingsNotifier(prefs: prefs);
  final relayNotifier = RelayNotifier(
    createRelayService: () => RelayService(
      idleTimeout: settingsNotifier.settings.idleTimeout,
      onLog: appLog.append,
    ),
    onStart: (server) =>
        settingsNotifier.update((s) => s.copyWith(lastServerId: server.id)),
  );

  runApp(GazooApp(
    appLog: appLog,
    serverListNotifier: serverListNotifier,
    settingsNotifier: settingsNotifier,
    relayNotifier: relayNotifier,
  ));
}

class GazooApp extends StatelessWidget {
  final AppLog appLog;
  final ServerListNotifier serverListNotifier;
  final SettingsNotifier settingsNotifier;
  final RelayNotifier relayNotifier;

  const GazooApp({
    super.key,
    required this.appLog,
    required this.serverListNotifier,
    required this.settingsNotifier,
    required this.relayNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appLog),
        ChangeNotifierProvider.value(value: serverListNotifier),
        ChangeNotifierProvider.value(value: settingsNotifier),
        ChangeNotifierProvider.value(value: relayNotifier),
      ],
      child: Consumer<SettingsNotifier>(
        builder: (context, notifier, _) {
          return MaterialApp(
            title: 'Gazoo',
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: notifier.settings.darkMode ? ThemeMode.dark : ThemeMode.light,
            home: notifier.settings.hasSeenOnboarding
                ? const HomeShell()
                : const OnboardingScreen(),
          );
        },
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;
  bool _autoStartAttempted = false;

  static const _tabs = [ServerListScreen(), SettingsScreen()];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_autoStartAttempted) {
      _autoStartAttempted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoStart());
    }
  }

  void _maybeAutoStart() {
    final settings = context.read<SettingsNotifier>().settings;
    if (!settings.autoStartLastServer || settings.lastServerId == null) return;
    final servers = context.read<ServerListNotifier>().servers;
    final matches = servers.where((s) => s.id == settings.lastServerId);
    if (matches.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ActiveRelayScreen(server: matches.first)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;
        final body = _tabs[_selectedIndex];

        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) => setState(() => _selectedIndex = index),
                  destinations: const [
                    NavigationRailDestination(icon: Icon(Icons.dns), label: Text('Servers')),
                    NavigationRailDestination(icon: Icon(Icons.settings), label: Text('Settings')),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }

        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) => setState(() => _selectedIndex = index),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.dns), label: 'Servers'),
              NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
            ],
          ),
        );
      },
    );
  }
}
