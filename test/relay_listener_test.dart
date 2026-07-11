import 'dart:async';
import 'dart:io';
import 'package:test/test.dart';
import 'package:gazoo/core/relay/relay_listener.dart';

/// A fake "real Minecraft server": echoes back whatever it receives,
/// prefixed with "echo:" so tests can distinguish request/response bytes.
class _FakeRemoteServer {
  late RawDatagramSocket _socket;
  int get port => _socket.port;

  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    _socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = _socket.receive();
      if (datagram == null) return;
      final reply = [...'echo:'.codeUnits, ...datagram.data];
      _socket.send(reply, datagram.address, datagram.port);
    });
  }

  void close() => _socket.close();
}

void main() {
  late _FakeRemoteServer fakeRemote;
  late RelayListener listener;

  setUp(() async {
    fakeRemote = _FakeRemoteServer();
    await fakeRemote.start();
  });

  tearDown(() async {
    await listener.stop();
    fakeRemote.close();
  });

  test('forwards a client datagram to the remote server and relays the reply back', () async {
    listener = RelayListener(
      bindAddress: InternetAddress.loopbackIPv4,
      listenPort: 0,
      remoteAddress: InternetAddress.loopbackIPv4,
      remotePort: fakeRemote.port,
    );
    await listener.start();

    final console = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(console.close);

    final replyCompleter = Completer<List<int>>();
    console.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = console.receive();
      if (datagram != null && !replyCompleter.isCompleted) {
        replyCompleter.complete(datagram.data);
      }
    });

    console.send('hello'.codeUnits, InternetAddress.loopbackIPv4, listener.boundPort);

    final reply = await replyCompleter.future.timeout(const Duration(seconds: 2));
    expect(String.fromCharCodes(reply), 'echo:hello');
  });

  test('two different clients get isolated sessions and correct replies', () async {
    listener = RelayListener(
      bindAddress: InternetAddress.loopbackIPv4,
      listenPort: 0,
      remoteAddress: InternetAddress.loopbackIPv4,
      remotePort: fakeRemote.port,
    );
    await listener.start();

    final clientA = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final clientB = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(clientA.close);
    addTearDown(clientB.close);

    final repliesA = <String>[];
    final repliesB = <String>[];
    clientA.listen((event) {
      if (event != RawSocketEvent.read) return;
      final d = clientA.receive();
      if (d != null) repliesA.add(String.fromCharCodes(d.data));
    });
    clientB.listen((event) {
      if (event != RawSocketEvent.read) return;
      final d = clientB.receive();
      if (d != null) repliesB.add(String.fromCharCodes(d.data));
    });

    clientA.send('from-a'.codeUnits, InternetAddress.loopbackIPv4, listener.boundPort);
    clientB.send('from-b'.codeUnits, InternetAddress.loopbackIPv4, listener.boundPort);

    await Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 50));
      return repliesA.isEmpty || repliesB.isEmpty;
    }).timeout(const Duration(seconds: 2));

    expect(repliesA, ['echo:from-a']);
    expect(repliesB, ['echo:from-b']);
    expect(listener.activeSessionCount, 2);
  });

  test('idle sessions are swept and closed after the timeout', () async {
    listener = RelayListener(
      bindAddress: InternetAddress.loopbackIPv4,
      listenPort: 0,
      remoteAddress: InternetAddress.loopbackIPv4,
      remotePort: fakeRemote.port,
      idleTimeout: const Duration(milliseconds: 100),
      sweepInterval: const Duration(milliseconds: 50),
    );
    await listener.start();

    final console = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(console.close);
    console.send('hi'.codeUnits, InternetAddress.loopbackIPv4, listener.boundPort);

    await Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 20));
      return listener.activeSessionCount == 0;
    }).timeout(const Duration(seconds: 1));
    expect(listener.activeSessionCount, 1);

    // sweepInterval is explicitly set fast (50ms) for this test; production
    // defaults to 10 seconds.
    await Future.delayed(const Duration(milliseconds: 250));
    expect(listener.activeSessionCount, 0);
  });

  test('bytesIn and bytesOut track forwarded traffic volume', () async {
    listener = RelayListener(
      bindAddress: InternetAddress.loopbackIPv4,
      listenPort: 0,
      remoteAddress: InternetAddress.loopbackIPv4,
      remotePort: fakeRemote.port,
    );
    await listener.start();

    final console = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(console.close);
    final replyCompleter = Completer<void>();
    console.listen((event) {
      if (event == RawSocketEvent.read) {
        console.receive();
        if (!replyCompleter.isCompleted) replyCompleter.complete();
      }
    });

    console.send('12345'.codeUnits, InternetAddress.loopbackIPv4, listener.boundPort);
    await replyCompleter.future.timeout(const Duration(seconds: 2));

    expect(listener.bytesOut, 5); // "12345"
    expect(listener.bytesIn, 10); // "echo:12345"
  });
}
