import 'dart:io';
import 'package:test/test.dart';
import 'package:gazoo/core/relay/session.dart';
import 'package:gazoo/core/relay/session_table.dart';

Future<RawDatagramSocket> _loopbackSocket() =>
    RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);

void main() {
  test('sessionKeyFor combines address and port', () {
    final key = sessionKeyFor(InternetAddress.loopbackIPv4, 5000);
    expect(key, '127.0.0.1:5000');
  });

  test('put and get round-trip a session by its key', () async {
    final socket = await _loopbackSocket();
    addTearDown(socket.close);
    final table = SessionTable();
    final session = RelaySession(
      key: 'client-a',
      clientAddress: InternetAddress.loopbackIPv4,
      clientPort: 4000,
      serverSocket: socket,
      lastActivity: DateTime.now(),
    );
    table.put(session);
    expect(table.get('client-a'), same(session));
    expect(table.get('missing'), isNull);
    expect(table.length, 1);
  });

  test('two sessions with different keys are isolated', () async {
    final socketA = await _loopbackSocket();
    final socketB = await _loopbackSocket();
    addTearDown(socketA.close);
    addTearDown(socketB.close);
    final table = SessionTable();
    table.put(RelaySession(
      key: 'a', clientAddress: InternetAddress.loopbackIPv4, clientPort: 1,
      serverSocket: socketA, lastActivity: DateTime.now(),
    ));
    table.put(RelaySession(
      key: 'b', clientAddress: InternetAddress.loopbackIPv4, clientPort: 2,
      serverSocket: socketB, lastActivity: DateTime.now(),
    ));
    expect(table.length, 2);
    expect(table.get('a')!.serverSocket, same(socketA));
    expect(table.get('b')!.serverSocket, same(socketB));
  });

  test('sweepExpired removes and closes only sessions past the timeout', () async {
    final freshSocket = await _loopbackSocket();
    final staleSocket = await _loopbackSocket();
    addTearDown(freshSocket.close);
    final table = SessionTable();
    final now = DateTime.now();
    table.put(RelaySession(
      key: 'fresh', clientAddress: InternetAddress.loopbackIPv4, clientPort: 1,
      serverSocket: freshSocket, lastActivity: now,
    ));
    table.put(RelaySession(
      key: 'stale', clientAddress: InternetAddress.loopbackIPv4, clientPort: 2,
      serverSocket: staleSocket, lastActivity: now.subtract(const Duration(minutes: 5)),
    ));

    final expired = table.sweepExpired(const Duration(seconds: 60), now);

    expect(expired.map((s) => s.key), ['stale']);
    expect(table.length, 1);
    expect(table.get('stale'), isNull);
    expect(table.get('fresh'), isNotNull);
  });

  test('touch updates lastActivity so the session survives the next sweep', () async {
    final socket = await _loopbackSocket();
    addTearDown(socket.close);
    final table = SessionTable();
    final start = DateTime.now().subtract(const Duration(minutes: 5));
    final session = RelaySession(
      key: 'k', clientAddress: InternetAddress.loopbackIPv4, clientPort: 1,
      serverSocket: socket, lastActivity: start,
    );
    table.put(session);
    session.touch(DateTime.now());

    final expired = table.sweepExpired(const Duration(seconds: 60), DateTime.now());

    expect(expired, isEmpty);
    expect(table.length, 1);
  });

  test('closeAll empties the table', () async {
    final socketA = await _loopbackSocket();
    final socketB = await _loopbackSocket();
    final table = SessionTable();
    table.put(RelaySession(
      key: 'a', clientAddress: InternetAddress.loopbackIPv4, clientPort: 1,
      serverSocket: socketA, lastActivity: DateTime.now(),
    ));
    table.put(RelaySession(
      key: 'b', clientAddress: InternetAddress.loopbackIPv4, clientPort: 2,
      serverSocket: socketB, lastActivity: DateTime.now(),
    ));

    table.closeAll();

    expect(table.length, 0);
  });
}
