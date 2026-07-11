import 'dart:io';

String sessionKeyFor(InternetAddress address, int port) => '${address.address}:$port';

class RelaySession {
  final String key;
  final InternetAddress clientAddress;
  final int clientPort;
  final RawDatagramSocket serverSocket;
  DateTime lastActivity;

  RelaySession({
    required this.key,
    required this.clientAddress,
    required this.clientPort,
    required this.serverSocket,
    required this.lastActivity,
  });

  void touch(DateTime now) => lastActivity = now;

  bool isExpired(Duration timeout, DateTime now) =>
      now.difference(lastActivity) > timeout;

  void close() => serverSocket.close();
}
