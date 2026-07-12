import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gazoo/core/config/server_config.dart';
import 'package:gazoo/core/discovery/server_prober.dart';
import 'package:gazoo/core/relay/relay_service.dart';
import 'package:gazoo/ui/screens/server_list_screen.dart';
import 'package:gazoo/ui/state/relay_notifier.dart';
import 'package:gazoo/ui/state/server_list_notifier.dart';

class _NoopRelayService implements RelayServiceHandle {
  @override
  Stream<RelayEvent> get events => const Stream.empty();
  @override
  Future<void> start(List<ServerConfig> servers) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

Widget _app(ServerListNotifier serverListNotifier) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: serverListNotifier),
      ChangeNotifierProvider(
        create: (_) => RelayNotifier(createRelayService: () => _NoopRelayService()),
      ),
    ],
    child: const MaterialApp(home: ServerListScreen()),
  );
}

void main() {
  late ServerListNotifier notifier;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    notifier = ServerListNotifier(
      prefs: prefs,
      probe: (host, port) async => const ServerStatus.offline('n/a'),
    );
  });

  testWidgets('shows empty state when there are no saved servers', (tester) async {
    await tester.pumpWidget(_app(notifier));

    expect(find.text('No servers yet. Tap + to add one.'), findsOneWidget);
  });

  testWidgets('adding a server via the form dialog shows it in the list', (tester) async {
    await tester.pumpWidget(_app(notifier));

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('server-name-field')), 'My Server');
    await tester.enterText(find.byKey(const Key('server-host-field')), 'example.com');
    await tester.enterText(find.byKey(const Key('server-port-field')), '19132');
    await tester.enterText(find.byKey(const Key('server-proxy-port-field')), '19133');

    await tester.tap(find.byKey(const Key('server-form-save-button')));
    await tester.pumpAndSettle();

    expect(find.text('My Server'), findsOneWidget);
    expect(notifier.servers, hasLength(1));
  });

  testWidgets('deleting a server removes its tile', (tester) async {
    await notifier.add(ServerConfig.create(
      name: 'Sample Server', host: 'example.com', port: 19132, proxyPort: 19133,
    ));
    await tester.pumpWidget(_app(notifier));
    await tester.pump();

    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(notifier.servers, isEmpty);
    expect(find.text('No servers yet. Tap + to add one.'), findsOneWidget);
  });

  testWidgets('tapping a server tile navigates to Active Relay', (tester) async {
    await notifier.add(ServerConfig.create(
      name: 'Sample Server', host: 'example.com', port: 19132, proxyPort: 19133,
    ));
    await tester.pumpWidget(_app(notifier));
    await tester.pump();

    await tester.tap(find.text('Sample Server'));
    await tester.pumpAndSettle();

    expect(find.text('Active Relay'), findsOneWidget);
  });
}
