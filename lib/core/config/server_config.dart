import 'dart:math';

class ServerConfig {
  final String id;
  final String name;
  final String host;
  final int port;
  final int serverGuid;
  final int proxyPort;

  const ServerConfig({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.serverGuid,
    required this.proxyPort,
  });

  factory ServerConfig.create({
    required String name,
    required String host,
    required int port,
    required int proxyPort,
  }) {
    final random = Random.secure();
    final id = List.generate(16, (_) => random.nextInt(16).toRadixString(16)).join();
    final serverGuid = random.nextInt(1 << 32) * (1 << 16) + random.nextInt(1 << 16) + 1;
    return ServerConfig(
      id: id,
      name: name,
      host: host,
      port: port,
      serverGuid: serverGuid,
      proxyPort: proxyPort,
    );
  }

  ServerConfig copyWith({
    String? name,
    String? host,
    int? port,
    int? proxyPort,
  }) {
    return ServerConfig(
      id: id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      serverGuid: serverGuid,
      proxyPort: proxyPort ?? this.proxyPort,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'serverGuid': serverGuid,
        'proxyPort': proxyPort,
      };

  factory ServerConfig.fromJson(Map<String, dynamic> json) => ServerConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        host: json['host'] as String,
        port: json['port'] as int,
        serverGuid: json['serverGuid'] as int,
        proxyPort: json['proxyPort'] as int,
      );
}
