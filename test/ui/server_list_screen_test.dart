import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gazoo/core/config/server_config.dart';
import 'package:gazoo/core/discovery/server_prober.dart';
import 'package:gazoo/core/relay/relay_service.dart';
import 'package:gazoo/ui/screens/active_relay_screen.dart';
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

  testWidgets('form rejects a server name containing ";"', (tester) async {
    await tester.pumpWidget(_app(notifier));

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('server-name-field')), 'Bad;Name');
    await tester.enterText(find.byKey(const Key('server-host-field')), 'example.com');
    await tester.enterText(find.byKey(const Key('server-port-field')), '19132');
    await tester.enterText(find.byKey(const Key('server-proxy-port-field')), '19133');

    await tester.tap(find.byKey(const Key('server-form-save-button')));
    await tester.pumpAndSettle();

    expect(find.text('Name cannot contain ";"'), findsOneWidget);
    expect(notifier.servers, isEmpty);
  });

  testWidgets('form rejects a proxy port of 19132 (reserved for discovery)', (tester) async {
    await tester.pumpWidget(_app(notifier));

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('server-name-field')), 'My Server');
    await tester.enterText(find.byKey(const Key('server-host-field')), 'example.com');
    await tester.enterText(find.byKey(const Key('server-port-field')), '19132');
    await tester.enterText(find.byKey(const Key('server-proxy-port-field')), '19132');

    await tester.tap(find.byKey(const Key('server-form-save-button')));
    await tester.pumpAndSettle();

    expect(find.text('19132 is reserved for discovery'), findsOneWidget);
    expect(notifier.servers, isEmpty);
  });

  testWidgets('deleting a server removes its tile', (tester) async {
    final server = ServerConfig.create(
      name: 'Sample Server', host: 'example.com', port: 19132, proxyPort: 19133,
    );
    await notifier.add(server);
    await tester.pumpWidget(_app(notifier));
    await tester.pump();

    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    await tester.tap(find.byKey(Key('delete-server-${server.id}')));
    await tester.pumpAndSettle();

    expect(notifier.servers, isEmpty);
    expect(find.text('No servers yet. Tap + to add one.'), findsOneWidget);
  });

  testWidgets('editing a server via its edit icon updates it in place', (tester) async {
    final server = ServerConfig.create(
      name: 'Sample Server', host: 'example.com', port: 19132, proxyPort: 19133,
    );
    await notifier.add(server);
    await tester.pumpWidget(_app(notifier));
    await tester.pump();

    await tester.tap(find.byKey(Key('edit-server-${server.id}')));
    await tester.pumpAndSettle();

    expect(find.text('Edit server'), findsOneWidget);
    final nameField = tester.widget<TextFormField>(find.byKey(const Key('server-name-field')));
    expect(nameField.controller!.text, 'Sample Server');

    await tester.enterText(find.byKey(const Key('server-name-field')), 'Renamed Server');
    await tester.tap(find.byKey(const Key('server-form-save-button')));
    await tester.pumpAndSettle();

    expect(find.text('Renamed Server'), findsOneWidget);
    expect(find.text('Sample Server'), findsNothing);
    expect(notifier.servers, hasLength(1));
    expect(notifier.servers.single.name, 'Renamed Server');
    expect(notifier.servers.single.id, server.id);
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

  testWidgets('rapid double-tap on a server tile only pushes one Active Relay screen', (tester) async {
    await notifier.add(ServerConfig.create(
      name: 'Sample Server', host: 'example.com', port: 19132, proxyPort: 19133,
    ));
    await tester.pumpWidget(_app(notifier));
    await tester.pump();

    await tester.tap(find.text('Sample Server'));
    // The first tap's push may already cover the tile with the new route's
    // barrier before this second tap lands — that's the point of the guard,
    // so don't fail the test over the resulting (expected) hit-test miss.
    await tester.tap(find.text('Sample Server'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(ActiveRelayScreen), findsOneWidget);
  });
}
