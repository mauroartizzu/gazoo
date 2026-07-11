import 'package:test/test.dart';
import 'package:gazoo/core/config/server_config.dart';

void main() {
  test('ServerConfig.create generates a non-empty id and serverGuid', () {
    final config = ServerConfig.create(
      name: 'My Server',
      host: 'example.com',
      port: 19132,
      proxyPort: 19133,
    );
    expect(config.id, isNotEmpty);
    expect(config.serverGuid, isNonZero);
    expect(config.name, 'My Server');
    expect(config.host, 'example.com');
    expect(config.port, 19132);
    expect(config.proxyPort, 19133);
  });

  test('ServerConfig.create generates distinct ids and guids across calls', () {
    final a = ServerConfig.create(name: 'A', host: 'a.com', port: 1, proxyPort: 2);
    final b = ServerConfig.create(name: 'B', host: 'b.com', port: 1, proxyPort: 3);
    expect(a.id, isNot(b.id));
    expect(a.serverGuid, isNot(b.serverGuid));
  });

  test('copyWith overrides only the given fields', () {
    final original = ServerConfig.create(name: 'A', host: 'a.com', port: 1, proxyPort: 2);
    final updated = original.copyWith(name: 'B');
    expect(updated.id, original.id);
    expect(updated.serverGuid, original.serverGuid);
    expect(updated.name, 'B');
    expect(updated.host, original.host);
  });

  test('toJson/fromJson round-trips all fields', () {
    final original = ServerConfig.create(name: 'A', host: 'a.com', port: 19132, proxyPort: 19133);
    final restored = ServerConfig.fromJson(original.toJson());
    expect(restored.id, original.id);
    expect(restored.name, original.name);
    expect(restored.host, original.host);
    expect(restored.port, original.port);
    expect(restored.serverGuid, original.serverGuid);
    expect(restored.proxyPort, original.proxyPort);
  });
}

final Matcher isNonZero = predicate<int>((v) => v != 0, 'is non-zero');
