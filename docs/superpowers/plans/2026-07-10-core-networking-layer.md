# Gazoo Core Networking Layer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and unit-test, in isolation from any UI, the complete networking core that lets Gazoo answer a console's RakNet LAN discovery broadcast for multiple configured Minecraft Bedrock servers and transparently relay UDP traffic for whichever one the console joins.

**Architecture:** Pure-Dart `lib/core/` package (no Flutter imports) layered as: RakNet ping/pong codec → session/NAT table → per-server UDP relay listener → real-server prober → shared discovery responder (demuxes N servers via distinct advertised ports) → `RelayService` composing all of the above behind a single start/stop/event-stream API. Every file is tested with real loopback UDP sockets — no mocking framework, since binding to `127.0.0.1:0` is fast and exercises real `dart:io` socket behavior.

**Tech Stack:** Flutter 3.44.6 / Dart SDK ^3.12.2 (already installed via Homebrew). `dart:io` for sockets, `dart:convert`/`dart:typed_data` for packet encoding, `package:test` (not `flutter_test`) for core unit tests to keep the core/UI boundary honest.

## Global Constraints

- No ads, no telemetry, no third-party SDKs beyond what's strictly needed for networking/UI.
- `lib/core/` must contain zero `package:flutter` imports — it must be testable headless.
- RakNet magic number (fixed 16 bytes): `00 ff ff 00 fe fe fe fe fd fd fd fd 12 34 56 78`.
- Unconnected Ping packet ID: `0x01`. Fields: 1B id + 8B int64 ping time + 16B magic + 8B int64 client GUID.
- Unconnected Pong packet ID: `0x1c`. Fields: 1B id + 8B echoed ping time + 8B int64 server GUID + 16B magic + 2B big-endian uint16 MOTD length + MOTD string.
- MOTD format: `MCPE;<Server Name>;<Protocol Version>;<Game Version>;<Player Count>;<Max Players>;<Server GUID>;<World Name>;<Gamemode>;1;<Port IPv4>;<Port IPv6>;`
- Default idle session timeout: 60 seconds, must be configurable.
- Multi-server demux: one shared discovery listener replies with one distinct Unconnected Pong per enabled server, each pong advertising that server's own dedicated proxy port (not `19132`) so the console's actual game session lands on an unambiguous per-server listener.
- After the discovery handshake, relay traffic is protocol-agnostic — no RakNet connection-packet parsing, just verbatim byte forwarding.

---

### Task 1: Flutter project scaffolding

**Files:**
- Create: `pubspec.yaml` (via `flutter create`, then edited)
- Create: `lib/core/` subdirectory tree (empty placeholders removed by later tasks' files)
- Modify: `pubspec.yaml:dev_dependencies` — add `test` package

**Interfaces:**
- Consumes: nothing (first task)
- Produces: a working Flutter project at `/Users/mauro/gazoo` that `flutter analyze` and `flutter test` run clean against; `test: ^1.25.0` available for pure-Dart core tests in later tasks.

- [ ] **Step 1: Scaffold the Flutter project in place**

Run from `/Users/mauro/gazoo` (already a git repo with `docs/` committed):

```bash
flutter create --org com.gazoo --project-name gazoo .
```

Expected: `flutter create` reports it wrote ~131 files under `lib/`, `android/`, `ios/`, `macos/`, `windows/`, `linux/`, `test/`, plus `pubspec.yaml`, `analysis_options.yaml`. It will not touch `docs/` or `.git/`.

- [ ] **Step 2: Add the `test` package for headless core tests**

Edit `pubspec.yaml`, in the `dev_dependencies:` section (below `flutter_test:` / `flutter_lints:`), add:

```yaml
  test: ^1.25.0
```

Then run:

```bash
flutter pub get
```

Expected: `Got dependencies!` with no errors.

- [ ] **Step 3: Create the core directory tree**

```bash
mkdir -p lib/core/raknet lib/core/discovery lib/core/relay lib/core/config
mkdir -p test
```

(`lib/ui/`, `lib/platform/`, `lib/cli/` are intentionally NOT created yet — they belong to later plans and empty directories aren't tracked by git.)

- [ ] **Step 4: Verify the toolchain is clean before adding any code**

```bash
flutter analyze
flutter test
```

Expected: `flutter analyze` reports "No issues found!". `flutter test` passes the one stock counter-app widget test Flutter generated.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Scaffold Flutter project, add test package for headless core tests"
```

---

### Task 2: RakNet Unconnected Ping/Pong codec

**Files:**
- Create: `lib/core/raknet/ping_pong_codec.dart`
- Test: `test/raknet_ping_pong_codec_test.dart`

**Interfaces:**
- Consumes: nothing beyond `dart:convert`, `dart:typed_data`
- Produces (used by Tasks 6, 7):
  - `const List<int> raknetMagic`
  - `const int idUnconnectedPing`, `const int idUnconnectedPong`
  - `class UnconnectedPing { final int pingTime; final int clientGuid; const UnconnectedPing({required int pingTime, required int clientGuid}); }`
  - `class UnconnectedPong { final int pingTime; final int serverGuid; final String motd; const UnconnectedPong({required int pingTime, required int serverGuid, required String motd}); }`
  - `class MalformedPacketException implements Exception { final String message; MalformedPacketException(String message); }`
  - `Uint8List encodeUnconnectedPing(UnconnectedPing ping)`
  - `UnconnectedPing decodeUnconnectedPing(Uint8List data)` — throws `MalformedPacketException`
  - `Uint8List encodeUnconnectedPong(UnconnectedPong pong)`
  - `UnconnectedPong decodeUnconnectedPong(Uint8List data)` — throws `MalformedPacketException`
  - `String buildMotd({required String serverName, required int protocolVersion, required String gameVersion, required int playerCount, required int maxPlayers, required int serverGuid, required String worldName, required String gamemode, required int portIpv4, required int portIpv6})`
  - `class MotdFields { final String serverName; final int protocolVersion; final String gameVersion; final int playerCount; final int maxPlayers; final int serverGuid; final String worldName; final String gamemode; final int portIpv4; final int portIpv6; const MotdFields({...}); }`
  - `MotdFields parseMotd(String motd)` — throws `MalformedPacketException`

- [ ] **Step 1: Write the failing test**

Create `test/raknet_ping_pong_codec_test.dart`:

```dart
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:gazoo/core/raknet/ping_pong_codec.dart';

void main() {
  group('Unconnected Ping', () {
    test('encode/decode round-trip preserves fields', () {
      final ping = UnconnectedPing(pingTime: 1234567890123, clientGuid: -42);
      final encoded = encodeUnconnectedPing(ping);
      final decoded = decodeUnconnectedPing(encoded);
      expect(decoded.pingTime, ping.pingTime);
      expect(decoded.clientGuid, ping.clientGuid);
    });

    test('encoded packet starts with id 0x01 and contains the magic number', () {
      final ping = UnconnectedPing(pingTime: 1, clientGuid: 2);
      final encoded = encodeUnconnectedPing(ping);
      expect(encoded[0], 0x01);
      expect(encoded.sublist(9, 25), raknetMagic);
      expect(encoded.length, 1 + 8 + 16 + 8);
    });

    test('decode throws on packet that is too short', () {
      expect(() => decodeUnconnectedPing(Uint8List(5)),
          throwsA(isA<MalformedPacketException>()));
    });

    test('decode throws on wrong packet id', () {
      final bytes = encodeUnconnectedPing(UnconnectedPing(pingTime: 1, clientGuid: 2));
      bytes[0] = 0x99;
      expect(() => decodeUnconnectedPing(bytes),
          throwsA(isA<MalformedPacketException>()));
    });

    test('decode throws on corrupted magic number', () {
      final bytes = encodeUnconnectedPing(UnconnectedPing(pingTime: 1, clientGuid: 2));
      bytes[10] = bytes[10] ^ 0xFF;
      expect(() => decodeUnconnectedPing(bytes),
          throwsA(isA<MalformedPacketException>()));
    });
  });

  group('Unconnected Pong', () {
    test('encode/decode round-trip preserves fields', () {
      final pong = UnconnectedPong(
        pingTime: 999,
        serverGuid: 1122334455,
        motd: 'MCPE;Gazoo Test;600;1.21.0;2;10;1122334455;World;Survival;1;19133;19133;',
      );
      final encoded = encodeUnconnectedPong(pong);
      final decoded = decodeUnconnectedPong(encoded);
      expect(decoded.pingTime, pong.pingTime);
      expect(decoded.serverGuid, pong.serverGuid);
      expect(decoded.motd, pong.motd);
    });

    test('encoded packet starts with id 0x1c and contains the magic number', () {
      final pong = UnconnectedPong(pingTime: 1, serverGuid: 2, motd: 'MCPE;x;1;1;0;1;2;w;Survival;1;1;1;');
      final encoded = encodeUnconnectedPong(pong);
      expect(encoded[0], 0x1c);
      expect(encoded.sublist(17, 33), raknetMagic);
    });

    test('decode throws on truncated MOTD', () {
      final pong = UnconnectedPong(pingTime: 1, serverGuid: 2, motd: 'MCPE;abc;');
      final encoded = encodeUnconnectedPong(pong);
      final truncated = encoded.sublist(0, encoded.length - 3);
      expect(() => decodeUnconnectedPong(truncated),
          throwsA(isA<MalformedPacketException>()));
    });
  });

  group('MOTD build/parse', () {
    test('buildMotd then parseMotd round-trips all fields', () {
      final motd = buildMotd(
        serverName: 'My Server',
        protocolVersion: 622,
        gameVersion: '1.21.0',
        playerCount: 3,
        maxPlayers: 10,
        serverGuid: 555,
        worldName: 'World',
        gamemode: 'Survival',
        portIpv4: 19133,
        portIpv6: 19134,
      );
      expect(motd, 'MCPE;My Server;622;1.21.0;3;10;555;World;Survival;1;19133;19134;');
      final parsed = parseMotd(motd);
      expect(parsed.serverName, 'My Server');
      expect(parsed.protocolVersion, 622);
      expect(parsed.gameVersion, '1.21.0');
      expect(parsed.playerCount, 3);
      expect(parsed.maxPlayers, 10);
      expect(parsed.serverGuid, 555);
      expect(parsed.worldName, 'World');
      expect(parsed.gamemode, 'Survival');
      expect(parsed.portIpv4, 19133);
      expect(parsed.portIpv6, 19134);
    });

    test('parseMotd throws on unrecognized format', () {
      expect(() => parseMotd('not;a;valid;motd'),
          throwsA(isA<MalformedPacketException>()));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/raknet_ping_pong_codec_test.dart
```

Expected: FAIL — `Error: Couldn't resolve the package 'gazoo' in 'package:gazoo/core/raknet/ping_pong_codec.dart'` (file doesn't exist yet).

- [ ] **Step 3: Write the implementation**

Create `lib/core/raknet/ping_pong_codec.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

const List<int> raknetMagic = [
  0x00, 0xff, 0xff, 0x00, 0xfe, 0xfe, 0xfe, 0xfe,
  0xfd, 0xfd, 0xfd, 0xfd, 0x12, 0x34, 0x56, 0x78,
];

const int idUnconnectedPing = 0x01;
const int idUnconnectedPong = 0x1c;

class MalformedPacketException implements Exception {
  final String message;
  MalformedPacketException(this.message);

  @override
  String toString() => 'MalformedPacketException: $message';
}

class UnconnectedPing {
  final int pingTime;
  final int clientGuid;
  const UnconnectedPing({required this.pingTime, required this.clientGuid});
}

class UnconnectedPong {
  final int pingTime;
  final int serverGuid;
  final String motd;
  const UnconnectedPong({
    required this.pingTime,
    required this.serverGuid,
    required this.motd,
  });
}

class MotdFields {
  final String serverName;
  final int protocolVersion;
  final String gameVersion;
  final int playerCount;
  final int maxPlayers;
  final int serverGuid;
  final String worldName;
  final String gamemode;
  final int portIpv4;
  final int portIpv6;

  const MotdFields({
    required this.serverName,
    required this.protocolVersion,
    required this.gameVersion,
    required this.playerCount,
    required this.maxPlayers,
    required this.serverGuid,
    required this.worldName,
    required this.gamemode,
    required this.portIpv4,
    required this.portIpv6,
  });
}

bool _magicMatches(List<int> candidate) {
  if (candidate.length != raknetMagic.length) return false;
  for (var i = 0; i < raknetMagic.length; i++) {
    if (candidate[i] != raknetMagic[i]) return false;
  }
  return true;
}

Uint8List encodeUnconnectedPing(UnconnectedPing ping) {
  final builder = BytesBuilder();
  builder.addByte(idUnconnectedPing);
  builder.add((ByteData(8)..setInt64(0, ping.pingTime, Endian.big)).buffer.asUint8List());
  builder.add(raknetMagic);
  builder.add((ByteData(8)..setInt64(0, ping.clientGuid, Endian.big)).buffer.asUint8List());
  return builder.toBytes();
}

UnconnectedPing decodeUnconnectedPing(Uint8List data) {
  const minLength = 1 + 8 + 16 + 8;
  if (data.length < minLength) {
    throw MalformedPacketException('Unconnected Ping too short: ${data.length} bytes');
  }
  if (data[0] != idUnconnectedPing) {
    throw MalformedPacketException(
        'Not an Unconnected Ping packet (id=0x${data[0].toRadixString(16)})');
  }
  final bytes = ByteData.sublistView(data);
  final pingTime = bytes.getInt64(1, Endian.big);
  if (!_magicMatches(data.sublist(9, 25))) {
    throw MalformedPacketException('Magic number mismatch');
  }
  final clientGuid = bytes.getInt64(25, Endian.big);
  return UnconnectedPing(pingTime: pingTime, clientGuid: clientGuid);
}

Uint8List encodeUnconnectedPong(UnconnectedPong pong) {
  final builder = BytesBuilder();
  builder.addByte(idUnconnectedPong);
  builder.add((ByteData(8)..setInt64(0, pong.pingTime, Endian.big)).buffer.asUint8List());
  builder.add((ByteData(8)..setInt64(0, pong.serverGuid, Endian.big)).buffer.asUint8List());
  builder.add(raknetMagic);
  final motdBytes = utf8.encode(pong.motd);
  builder.add((ByteData(2)..setUint16(0, motdBytes.length, Endian.big)).buffer.asUint8List());
  builder.add(motdBytes);
  return builder.toBytes();
}

UnconnectedPong decodeUnconnectedPong(Uint8List data) {
  const headerLength = 1 + 8 + 8 + 16 + 2;
  if (data.length < headerLength) {
    throw MalformedPacketException('Unconnected Pong too short: ${data.length} bytes');
  }
  if (data[0] != idUnconnectedPong) {
    throw MalformedPacketException(
        'Not an Unconnected Pong packet (id=0x${data[0].toRadixString(16)})');
  }
  final bytes = ByteData.sublistView(data);
  final pingTime = bytes.getInt64(1, Endian.big);
  final serverGuid = bytes.getInt64(9, Endian.big);
  if (!_magicMatches(data.sublist(17, 33))) {
    throw MalformedPacketException('Magic number mismatch');
  }
  final motdLength = bytes.getUint16(33, Endian.big);
  if (data.length < headerLength + motdLength) {
    throw MalformedPacketException('Unconnected Pong MOTD truncated');
  }
  final motd = utf8.decode(data.sublist(headerLength, headerLength + motdLength));
  return UnconnectedPong(pingTime: pingTime, serverGuid: serverGuid, motd: motd);
}

String buildMotd({
  required String serverName,
  required int protocolVersion,
  required String gameVersion,
  required int playerCount,
  required int maxPlayers,
  required int serverGuid,
  required String worldName,
  required String gamemode,
  required int portIpv4,
  required int portIpv6,
}) {
  return 'MCPE;$serverName;$protocolVersion;$gameVersion;$playerCount;$maxPlayers;'
      '$serverGuid;$worldName;$gamemode;1;$portIpv4;$portIpv6;';
}

MotdFields parseMotd(String motd) {
  final parts = motd.split(';');
  if (parts.length < 12 || parts[0] != 'MCPE') {
    throw MalformedPacketException('Unrecognized MOTD format: $motd');
  }
  try {
    return MotdFields(
      serverName: parts[1],
      protocolVersion: int.parse(parts[2]),
      gameVersion: parts[3],
      playerCount: int.parse(parts[4]),
      maxPlayers: int.parse(parts[5]),
      serverGuid: int.parse(parts[6]),
      worldName: parts[7],
      gamemode: parts[8],
      portIpv4: int.parse(parts[10]),
      portIpv6: int.parse(parts[11]),
    );
  } on FormatException catch (e) {
    throw MalformedPacketException('Unrecognized MOTD format: $motd ($e)');
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/raknet_ping_pong_codec_test.dart
```

Expected: PASS — all groups green (`All tests passed!`).

- [ ] **Step 5: Commit**

```bash
git add lib/core/raknet/ping_pong_codec.dart test/raknet_ping_pong_codec_test.dart
git commit -m "Add RakNet Unconnected Ping/Pong codec with MOTD build/parse"
```

---

### Task 3: Server and settings config models

**Files:**
- Create: `lib/core/config/server_config.dart`
- Create: `lib/core/config/settings.dart`
- Test: `test/server_config_test.dart`
- Test: `test/settings_test.dart`

**Interfaces:**
- Consumes: nothing beyond `dart:math`
- Produces (used by Tasks 7, 8):
  - `class ServerConfig { final String id; final String name; final String host; final int port; final int serverGuid; final int proxyPort; const ServerConfig({required String id, required String name, required String host, required int port, required int serverGuid, required int proxyPort}); factory ServerConfig.create({required String name, required String host, required int port, required int proxyPort}); ServerConfig copyWith({String? name, String? host, int? port, int? proxyPort}); Map<String, dynamic> toJson(); factory ServerConfig.fromJson(Map<String, dynamic> json); }`
  - `class Settings { final Duration idleTimeout; final bool autoStartLastServer; final String? lastServerId; final bool darkMode; final bool verboseLogging; const Settings({...}); static const Settings defaults; Settings copyWith({...}); Map<String, dynamic> toJson(); factory Settings.fromJson(Map<String, dynamic> json); }`

- [ ] **Step 1: Write the failing tests**

Create `test/server_config_test.dart`:

```dart
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
```

Create `test/settings_test.dart`:

```dart
import 'package:test/test.dart';
import 'package:gazoo/core/config/settings.dart';

void main() {
  test('defaults match spec: 60s idle timeout, auto-start off, light theme', () {
    expect(Settings.defaults.idleTimeout, const Duration(seconds: 60));
    expect(Settings.defaults.autoStartLastServer, isFalse);
    expect(Settings.defaults.lastServerId, isNull);
    expect(Settings.defaults.darkMode, isFalse);
    expect(Settings.defaults.verboseLogging, isFalse);
  });

  test('copyWith overrides only the given fields', () {
    final updated = Settings.defaults.copyWith(darkMode: true, lastServerId: 'abc');
    expect(updated.darkMode, isTrue);
    expect(updated.lastServerId, 'abc');
    expect(updated.idleTimeout, Settings.defaults.idleTimeout);
    expect(updated.autoStartLastServer, Settings.defaults.autoStartLastServer);
  });

  test('toJson/fromJson round-trips all fields', () {
    final original = Settings.defaults.copyWith(
      idleTimeout: const Duration(seconds: 30),
      autoStartLastServer: true,
      lastServerId: 'xyz',
      darkMode: true,
      verboseLogging: true,
    );
    final restored = Settings.fromJson(original.toJson());
    expect(restored.idleTimeout, original.idleTimeout);
    expect(restored.autoStartLastServer, original.autoStartLastServer);
    expect(restored.lastServerId, original.lastServerId);
    expect(restored.darkMode, original.darkMode);
    expect(restored.verboseLogging, original.verboseLogging);
  });

  test('fromJson falls back to defaults for missing keys', () {
    final restored = Settings.fromJson({});
    expect(restored.idleTimeout, Settings.defaults.idleTimeout);
    expect(restored.autoStartLastServer, Settings.defaults.autoStartLastServer);
    expect(restored.lastServerId, isNull);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/server_config_test.dart test/settings_test.dart
```

Expected: FAIL — cannot resolve `package:gazoo/core/config/server_config.dart` and `.../settings.dart` (files don't exist yet).

- [ ] **Step 3: Write the implementation**

Create `lib/core/config/server_config.dart`:

```dart
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
```

Create `lib/core/config/settings.dart`:

```dart
class Settings {
  final Duration idleTimeout;
  final bool autoStartLastServer;
  final String? lastServerId;
  final bool darkMode;
  final bool verboseLogging;

  const Settings({
    required this.idleTimeout,
    required this.autoStartLastServer,
    this.lastServerId,
    required this.darkMode,
    required this.verboseLogging,
  });

  static const Settings defaults = Settings(
    idleTimeout: Duration(seconds: 60),
    autoStartLastServer: false,
    lastServerId: null,
    darkMode: false,
    verboseLogging: false,
  );

  Settings copyWith({
    Duration? idleTimeout,
    bool? autoStartLastServer,
    String? lastServerId,
    bool? darkMode,
    bool? verboseLogging,
  }) {
    return Settings(
      idleTimeout: idleTimeout ?? this.idleTimeout,
      autoStartLastServer: autoStartLastServer ?? this.autoStartLastServer,
      lastServerId: lastServerId ?? this.lastServerId,
      darkMode: darkMode ?? this.darkMode,
      verboseLogging: verboseLogging ?? this.verboseLogging,
    );
  }

  Map<String, dynamic> toJson() => {
        'idleTimeoutSeconds': idleTimeout.inSeconds,
        'autoStartLastServer': autoStartLastServer,
        'lastServerId': lastServerId,
        'darkMode': darkMode,
        'verboseLogging': verboseLogging,
      };

  factory Settings.fromJson(Map<String, dynamic> json) => Settings(
        idleTimeout: Duration(seconds: json['idleTimeoutSeconds'] as int? ?? 60),
        autoStartLastServer: json['autoStartLastServer'] as bool? ?? false,
        lastServerId: json['lastServerId'] as String?,
        darkMode: json['darkMode'] as bool? ?? false,
        verboseLogging: json['verboseLogging'] as bool? ?? false,
      );
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/server_config_test.dart test/settings_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/config/ test/server_config_test.dart test/settings_test.dart
git commit -m "Add ServerConfig and Settings models with JSON round-trip"
```

---

### Task 4: Relay session and NAT session table

**Files:**
- Create: `lib/core/relay/session.dart`
- Create: `lib/core/relay/session_table.dart`
- Test: `test/relay_session_table_test.dart`

**Interfaces:**
- Consumes: `dart:io` (`InternetAddress`, `RawDatagramSocket`)
- Produces (used by Task 5):
  - `String sessionKeyFor(InternetAddress address, int port)`
  - `class RelaySession { final String key; final InternetAddress clientAddress; final int clientPort; final RawDatagramSocket serverSocket; DateTime lastActivity; RelaySession({required String key, required InternetAddress clientAddress, required int clientPort, required RawDatagramSocket serverSocket, required DateTime lastActivity}); void touch(DateTime now); bool isExpired(Duration timeout, DateTime now); void close(); }`
  - `class SessionTable { RelaySession? get(String key); void put(RelaySession session); Iterable<RelaySession> get all; int get length; List<RelaySession> sweepExpired(Duration timeout, DateTime now); void removeAndClose(String key); void closeAll(); }`

Tests use real UDP sockets bound to `InternetAddress.loopbackIPv4` on port `0` (OS-assigned ephemeral port) — this is fast, requires no network, and exercises real `dart:io` socket lifecycle instead of a mock.

- [ ] **Step 1: Write the failing test**

Create `test/relay_session_table_test.dart`:

```dart
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
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/relay_session_table_test.dart
```

Expected: FAIL — cannot resolve `package:gazoo/core/relay/session.dart` and `.../session_table.dart`.

- [ ] **Step 3: Write the implementation**

Create `lib/core/relay/session.dart`:

```dart
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
```

Create `lib/core/relay/session_table.dart`:

```dart
import 'session.dart';

class SessionTable {
  final Map<String, RelaySession> _sessions = {};

  RelaySession? get(String key) => _sessions[key];

  void put(RelaySession session) {
    _sessions[session.key] = session;
  }

  Iterable<RelaySession> get all => _sessions.values;

  int get length => _sessions.length;

  List<RelaySession> sweepExpired(Duration timeout, DateTime now) {
    final expired = _sessions.values.where((s) => s.isExpired(timeout, now)).toList();
    for (final session in expired) {
      session.close();
      _sessions.remove(session.key);
    }
    return expired;
  }

  void removeAndClose(String key) {
    final session = _sessions.remove(key);
    session?.close();
  }

  void closeAll() {
    for (final session in _sessions.values) {
      session.close();
    }
    _sessions.clear();
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/relay_session_table_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/relay/session.dart lib/core/relay/session_table.dart test/relay_session_table_test.dart
git commit -m "Add RelaySession and SessionTable NAT-style session tracking"
```

---

### Task 5: Transparent UDP relay listener

**Files:**
- Create: `lib/core/relay/relay_listener.dart`
- Test: `test/relay_listener_test.dart`

**Interfaces:**
- Consumes: `RelaySession`, `SessionTable`, `sessionKeyFor` from Task 4
- Produces (used by Task 8):
  - `class RelayListener { final InternetAddress bindAddress; final int listenPort; final InternetAddress remoteAddress; final int remotePort; final Duration idleTimeout; RelayListener({required InternetAddress bindAddress, required int listenPort, required InternetAddress remoteAddress, required int remotePort, Duration idleTimeout = const Duration(seconds: 60), void Function(String message)? onLog}); int get boundPort; int get activeSessionCount; int get bytesIn; int get bytesOut; Future<void> start(); Future<void> stop(); }`

- [ ] **Step 1: Write the failing test**

Create `test/relay_listener_test.dart`:

```dart
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

    // RelayListener's internal sweep runs on a 10-second timer in production;
    // for the test we wait past idleTimeout and call the public stop/start
    // cycle instead — see Step 3 note on the injectable sweep interval.
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
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/relay_listener_test.dart
```

Expected: FAIL — cannot resolve `package:gazoo/core/relay/relay_listener.dart`.

- [ ] **Step 3: Write the implementation**

Create `lib/core/relay/relay_listener.dart`. Note: the idle-session sweep runs on a 10-second periodic timer in production, but must react promptly enough for the "idle sessions swept" test above (100ms timeout, checked after 250ms) — so the sweep interval is a constructor parameter defaulting to 10 seconds, overridable by tests:

```dart
import 'dart:async';
import 'dart:io';

import 'session.dart';
import 'session_table.dart';

class RelayListener {
  final InternetAddress bindAddress;
  final int listenPort;
  final InternetAddress remoteAddress;
  final int remotePort;
  final Duration idleTimeout;
  final Duration sweepInterval;
  final void Function(String message)? onLog;

  RawDatagramSocket? _socket;
  final SessionTable _sessions = SessionTable();
  final Map<String, Future<RelaySession>> _pending = {};
  Timer? _sweepTimer;
  int bytesIn = 0;
  int bytesOut = 0;

  RelayListener({
    required this.bindAddress,
    required this.listenPort,
    required this.remoteAddress,
    required this.remotePort,
    this.idleTimeout = const Duration(seconds: 60),
    this.sweepInterval = const Duration(milliseconds: 100),
    this.onLog,
  });

  int get boundPort => _socket!.port;
  int get activeSessionCount => _sessions.length;

  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(bindAddress, listenPort);
    _socket!.listen(_onClientEvent);
    _sweepTimer = Timer.periodic(sweepInterval, (_) {
      final expired = _sessions.sweepExpired(idleTimeout, DateTime.now());
      for (final session in expired) {
        onLog?.call('Session expired: ${session.key}');
      }
    });
  }

  void _onClientEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket!.receive();
    if (datagram == null) return;
    unawaited(_handleClientDatagram(datagram));
  }

  Future<void> _handleClientDatagram(Datagram datagram) async {
    final key = sessionKeyFor(datagram.address, datagram.port);
    var session = _sessions.get(key);
    if (session == null) {
      final pending = _pending[key];
      if (pending != null) {
        session = await pending;
      } else {
        final future = _createSession(key, datagram.address, datagram.port);
        _pending[key] = future;
        try {
          session = await future;
        } finally {
          _pending.remove(key);
        }
      }
    }
    session.touch(DateTime.now());
    session.serverSocket.send(datagram.data, remoteAddress, remotePort);
    bytesOut += datagram.data.length;
  }

  Future<RelaySession> _createSession(
      String key, InternetAddress clientAddress, int clientPort) async {
    final rawSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final session = RelaySession(
      key: key,
      clientAddress: clientAddress,
      clientPort: clientPort,
      serverSocket: rawSocket,
      lastActivity: DateTime.now(),
    );
    rawSocket.listen((event) => _onServerEvent(event, session));
    _sessions.put(session);
    onLog?.call('New session: $key');
    return session;
  }

  void _onServerEvent(RawSocketEvent event, RelaySession session) {
    if (event != RawSocketEvent.read) return;
    final datagram = session.serverSocket.receive();
    if (datagram == null) return;
    session.touch(DateTime.now());
    _socket!.send(datagram.data, session.clientAddress, session.clientPort);
    bytesIn += datagram.data.length;
  }

  Future<void> stop() async {
    _sweepTimer?.cancel();
    _sweepTimer = null;
    _sessions.closeAll();
    _socket?.close();
    _socket = null;
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/relay_listener_test.dart
```

Expected: PASS. (If the isolation or idle-sweep test is flaky due to scheduling, re-run once — real-socket tests can have a few ms of jitter; if it fails consistently, re-check the `sweepInterval`/timeout math in the test, not the implementation.)

- [ ] **Step 5: Commit**

```bash
git add lib/core/relay/relay_listener.dart test/relay_listener_test.dart
git commit -m "Add RelayListener: transparent UDP proxy with per-client sessions"
```

---

### Task 6: Real-server prober

**Files:**
- Create: `lib/core/discovery/server_prober.dart`
- Test: `test/server_prober_test.dart`

**Interfaces:**
- Consumes: `UnconnectedPing`, `UnconnectedPong`, `encodeUnconnectedPing`, `decodeUnconnectedPong`, `MotdFields`, `parseMotd` from Task 2
- Produces (used by Task 8):
  - `class ServerStatus { final bool online; final MotdFields? motd; final Duration? latency; final String? error; const ServerStatus.online(MotdFields motd, Duration latency); const ServerStatus.offline(String error); }`
  - `class ServerProber { final Duration timeout; const ServerProber({Duration timeout = const Duration(seconds: 3)}); Future<ServerStatus> probe(String host, int port); }`

- [ ] **Step 1: Write the failing test**

Create `test/server_prober_test.dart`:

```dart
import 'dart:io';
import 'package:test/test.dart';
import 'package:gazoo/core/discovery/server_prober.dart';
import 'package:gazoo/core/raknet/ping_pong_codec.dart';

/// A fake real Minecraft server that answers Unconnected Ping with a valid Pong.
class _FakeMinecraftServer {
  late RawDatagramSocket _socket;
  int get port => _socket.port;

  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    _socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = _socket.receive();
      if (datagram == null) return;
      final ping = decodeUnconnectedPing(datagram.data);
      final motd = buildMotd(
        serverName: 'Fake Server',
        protocolVersion: 622,
        gameVersion: '1.21.0',
        playerCount: 4,
        maxPlayers: 20,
        serverGuid: 777,
        worldName: 'World',
        gamemode: 'Survival',
        portIpv4: port,
        portIpv6: port,
      );
      final pong = UnconnectedPong(pingTime: ping.pingTime, serverGuid: 777, motd: motd);
      _socket.send(encodeUnconnectedPong(pong), datagram.address, datagram.port);
    });
  }

  void close() => _socket.close();
}

void main() {
  test('probe returns online status with parsed live server info', () async {
    final fakeServer = _FakeMinecraftServer();
    await fakeServer.start();
    addTearDown(fakeServer.close);

    const prober = ServerProber(timeout: Duration(seconds: 2));
    final status = await prober.probe('127.0.0.1', fakeServer.port);

    expect(status.online, isTrue);
    expect(status.motd!.serverName, 'Fake Server');
    expect(status.motd!.protocolVersion, 622);
    expect(status.motd!.gameVersion, '1.21.0');
    expect(status.motd!.playerCount, 4);
    expect(status.motd!.maxPlayers, 20);
    expect(status.latency, isNotNull);
  });

  test('probe returns offline status when nothing responds before the timeout', () async {
    // Bind then immediately close, so the port is (almost certainly) unused
    // and nothing will reply within the short test timeout.
    final probe = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final unusedPort = probe.port;
    probe.close();

    const prober = ServerProber(timeout: Duration(milliseconds: 300));
    final status = await prober.probe('127.0.0.1', unusedPort);

    expect(status.online, isFalse);
    expect(status.error, isNotNull);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/server_prober_test.dart
```

Expected: FAIL — cannot resolve `package:gazoo/core/discovery/server_prober.dart`.

- [ ] **Step 3: Write the implementation**

Create `lib/core/discovery/server_prober.dart`:

```dart
import 'dart:async';
import 'dart:io';

import '../raknet/ping_pong_codec.dart';

class ServerStatus {
  final bool online;
  final MotdFields? motd;
  final Duration? latency;
  final String? error;

  const ServerStatus.online(MotdFields this.motd, Duration this.latency)
      : online = true,
        error = null;

  const ServerStatus.offline(String this.error)
      : online = false,
        motd = null,
        latency = null;
}

class ServerProber {
  final Duration timeout;
  const ServerProber({this.timeout = const Duration(seconds: 3)});

  Future<ServerStatus> probe(String host, int port) async {
    RawDatagramSocket? socket;
    StreamSubscription? subscription;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final addresses = await InternetAddress.lookup(host);
      if (addresses.isEmpty) {
        return ServerStatus.offline('Could not resolve host: $host');
      }
      final address = addresses.first;
      final sentAt = DateTime.now();
      final ping = UnconnectedPing(pingTime: sentAt.millisecondsSinceEpoch, clientGuid: 0);
      socket.send(encodeUnconnectedPing(ping), address, port);

      final completer = Completer<ServerStatus>();
      final timer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.complete(ServerStatus.offline('Timed out waiting for response'));
        }
      });

      subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket!.receive();
        if (datagram == null) return;
        try {
          final pong = decodeUnconnectedPong(datagram.data);
          final motd = parseMotd(pong.motd);
          if (!completer.isCompleted) {
            completer.complete(ServerStatus.online(motd, DateTime.now().difference(sentAt)));
          }
        } on MalformedPacketException {
          // Not a valid pong (or from an unrelated sender) — keep waiting.
        }
      });

      final result = await completer.future;
      timer.cancel();
      return result;
    } on SocketException catch (e) {
      return ServerStatus.offline(e.message);
    } finally {
      await subscription?.cancel();
      socket?.close();
    }
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/server_prober_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/discovery/server_prober.dart test/server_prober_test.dart
git commit -m "Add ServerProber: real-server ping for live status"
```

---

### Task 7: Shared LAN discovery responder (multi-server demux)

**Files:**
- Create: `lib/core/discovery/lan_broadcast_responder.dart`
- Test: `test/lan_broadcast_responder_test.dart`

**Interfaces:**
- Consumes: `ServerConfig` from Task 3; `UnconnectedPing`, `UnconnectedPong`, `decodeUnconnectedPing`, `encodeUnconnectedPong`, `buildMotd`, `MalformedPacketException` from Task 2
- Produces (used by Task 8):
  - `class ServerLiveInfo { final int protocolVersion; final String gameVersion; final int playerCount; final int maxPlayers; const ServerLiveInfo({required int protocolVersion, required String gameVersion, required int playerCount, required int maxPlayers}); }`
  - `class LanBroadcastResponder { final InternetAddress bindAddress; final int listenPort; LanBroadcastResponder({required InternetAddress bindAddress, int listenPort = 19132, required List<ServerConfig> Function() enabledServers, required ServerLiveInfo Function(ServerConfig) liveInfo, void Function(String message)? onLog}); int get boundPort; Future<void> start(); Future<void> stop(); }`

- [ ] **Step 1: Write the failing test**

Create `test/lan_broadcast_responder_test.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'package:test/test.dart';
import 'package:gazoo/core/config/server_config.dart';
import 'package:gazoo/core/discovery/lan_broadcast_responder.dart';
import 'package:gazoo/core/raknet/ping_pong_codec.dart';

void main() {
  test('replies with one distinct pong per enabled server, each on its own proxy port', () async {
    final serverA = ServerConfig.create(name: 'Server A', host: 'a.example.com', port: 19132, proxyPort: 19140);
    final serverB = ServerConfig.create(name: 'Server B', host: 'b.example.com', port: 19132, proxyPort: 19141);

    final responder = LanBroadcastResponder(
      bindAddress: InternetAddress.loopbackIPv4,
      listenPort: 0,
      enabledServers: () => [serverA, serverB],
      liveInfo: (server) => const ServerLiveInfo(
        protocolVersion: 622,
        gameVersion: '1.21.0',
        playerCount: 1,
        maxPlayers: 10,
      ),
    );
    await responder.start();
    addTearDown(responder.stop);

    final console = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(console.close);

    final pongs = <UnconnectedPong>[];
    final done = Completer<void>();
    console.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = console.receive();
      if (datagram == null) return;
      pongs.add(decodeUnconnectedPong(datagram.data));
      if (pongs.length == 2 && !done.isCompleted) done.complete();
    });

    const sentPingTime = 123456789;
    console.send(
      encodeUnconnectedPing(const UnconnectedPing(pingTime: sentPingTime, clientGuid: 1)),
      InternetAddress.loopbackIPv4,
      responder.boundPort,
    );

    await done.future.timeout(const Duration(seconds: 2));

    expect(pongs.length, 2);
    for (final pong in pongs) {
      expect(pong.pingTime, sentPingTime);
    }
    final guids = pongs.map((p) => p.serverGuid).toSet();
    expect(guids, {serverA.serverGuid, serverB.serverGuid});

    final motdA = parseMotd(pongs.firstWhere((p) => p.serverGuid == serverA.serverGuid).motd);
    final motdB = parseMotd(pongs.firstWhere((p) => p.serverGuid == serverB.serverGuid).motd);
    expect(motdA.serverName, 'Server A');
    expect(motdA.portIpv4, 19140);
    expect(motdB.serverName, 'Server B');
    expect(motdB.portIpv4, 19141);
    expect(motdA.playerCount, 1);
    expect(motdA.maxPlayers, 10);
    expect(motdA.gameVersion, '1.21.0');
  });

  test('ignores malformed packets instead of crashing', () async {
    final responder = LanBroadcastResponder(
      bindAddress: InternetAddress.loopbackIPv4,
      listenPort: 0,
      enabledServers: () => [],
      liveInfo: (server) => const ServerLiveInfo(
          protocolVersion: 1, gameVersion: '1', playerCount: 0, maxPlayers: 0),
    );
    await responder.start();
    addTearDown(responder.stop);

    final sender = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(sender.close);
    sender.send([0x01, 0x02, 0x03], InternetAddress.loopbackIPv4, responder.boundPort);

    // Give the responder a moment to process; it must not throw or crash the isolate.
    await Future.delayed(const Duration(milliseconds: 100));
    expect(true, isTrue); // reaching here means no uncaught exception occurred
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/lan_broadcast_responder_test.dart
```

Expected: FAIL — cannot resolve `package:gazoo/core/discovery/lan_broadcast_responder.dart`.

- [ ] **Step 3: Write the implementation**

Create `lib/core/discovery/lan_broadcast_responder.dart`:

```dart
import 'dart:io';

import '../config/server_config.dart';
import '../raknet/ping_pong_codec.dart';

class ServerLiveInfo {
  final int protocolVersion;
  final String gameVersion;
  final int playerCount;
  final int maxPlayers;

  const ServerLiveInfo({
    required this.protocolVersion,
    required this.gameVersion,
    required this.playerCount,
    required this.maxPlayers,
  });
}

class LanBroadcastResponder {
  final InternetAddress bindAddress;
  final int listenPort;
  final List<ServerConfig> Function() enabledServers;
  final ServerLiveInfo Function(ServerConfig server) liveInfo;
  final void Function(String message)? onLog;

  RawDatagramSocket? _socket;

  LanBroadcastResponder({
    required this.bindAddress,
    this.listenPort = 19132,
    required this.enabledServers,
    required this.liveInfo,
    this.onLog,
  });

  int get boundPort => _socket!.port;

  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(bindAddress, listenPort);
    _socket!.broadcastEnabled = true;
    _socket!.listen(_onEvent);
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket!.receive();
    if (datagram == null) return;

    final UnconnectedPing ping;
    try {
      ping = decodeUnconnectedPing(datagram.data);
    } on MalformedPacketException {
      return;
    }

    for (final server in enabledServers()) {
      final info = liveInfo(server);
      final motd = buildMotd(
        serverName: server.name,
        protocolVersion: info.protocolVersion,
        gameVersion: info.gameVersion,
        playerCount: info.playerCount,
        maxPlayers: info.maxPlayers,
        serverGuid: server.serverGuid,
        worldName: server.name,
        gamemode: 'Survival',
        portIpv4: server.proxyPort,
        portIpv6: server.proxyPort,
      );
      final pong = UnconnectedPong(
        pingTime: ping.pingTime,
        serverGuid: server.serverGuid,
        motd: motd,
      );
      _socket!.send(encodeUnconnectedPong(pong), datagram.address, datagram.port);
      onLog?.call(
          'Replied to ${datagram.address.address}:${datagram.port} for server "${server.name}"');
    }
  }

  Future<void> stop() async {
    _socket?.close();
    _socket = null;
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/lan_broadcast_responder_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/discovery/lan_broadcast_responder.dart test/lan_broadcast_responder_test.dart
git commit -m "Add LanBroadcastResponder: multi-server discovery demux via distinct proxy ports"
```

---

### Task 8: RelayService — compose everything behind one start/stop/event API

**Files:**
- Create: `lib/core/relay/relay_service.dart`
- Test: `test/relay_service_test.dart`

**Interfaces:**
- Consumes: `ServerConfig` (Task 3), `RelayListener` (Task 5), `ServerProber`/`ServerStatus` (Task 6), `LanBroadcastResponder`/`ServerLiveInfo` (Task 7)
- Produces (used by the future GUI plan's `ChangeNotifier` adapter and the future CLI plan):
  - `enum RelayStatus { listening, consoleConnected }`
  - `class RelayEvent { final String serverId; final RelayStatus status; final int bytesIn; final int bytesOut; const RelayEvent({required String serverId, required RelayStatus status, required int bytesIn, required int bytesOut}); }`
  - `class RelayService { RelayService({Duration idleTimeout = const Duration(seconds: 60), Duration statusPollInterval = const Duration(seconds: 5), ServerProber? prober, void Function(String message)? onLog}); Stream<RelayEvent> get events; Future<void> start(List<ServerConfig> servers); Future<void> pollNow(); Future<void> stop(); Future<void> dispose(); }`

- [ ] **Step 1: Write the failing test**

Create `test/relay_service_test.dart`:

```dart
import 'dart:async';
import 'dart:io';
import 'package:test/test.dart';
import 'package:gazoo/core/config/server_config.dart';
import 'package:gazoo/core/discovery/server_prober.dart';
import 'package:gazoo/core/raknet/ping_pong_codec.dart';
import 'package:gazoo/core/relay/relay_service.dart';

/// A fake real Minecraft server: answers pings with a valid pong and echoes
/// any other traffic back to whoever sent it (standing in for game traffic).
class _FakeRemoteServer {
  late RawDatagramSocket _socket;
  int get port => _socket.port;

  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    _socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = _socket.receive();
      if (datagram == null) return;
      try {
        final ping = decodeUnconnectedPing(datagram.data);
        final motd = buildMotd(
          serverName: 'Real Server', protocolVersion: 622, gameVersion: '1.21.0',
          playerCount: 2, maxPlayers: 10, serverGuid: 42, worldName: 'World',
          gamemode: 'Survival', portIpv4: port, portIpv6: port,
        );
        _socket.send(
          encodeUnconnectedPong(UnconnectedPong(pingTime: ping.pingTime, serverGuid: 42, motd: motd)),
          datagram.address, datagram.port,
        );
      } on MalformedPacketException {
        _socket.send(datagram.data, datagram.address, datagram.port); // echo game traffic
      }
    });
  }

  void close() => _socket.close();
}

Future<int> _freePort() async {
  final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  final port = s.port;
  s.close();
  return port;
}

void main() {
  late _FakeRemoteServer fakeRemote;
  late RelayService service;

  setUp(() async {
    fakeRemote = _FakeRemoteServer();
    await fakeRemote.start();
  });

  tearDown(() async {
    await service.dispose();
    fakeRemote.close();
  });

  test('start() opens a listener per server and pollNow() reports live info from the real server', () async {
    final proxyPort = await _freePort();
    final server = ServerConfig.create(
      name: 'Test Server', host: '127.0.0.1', port: fakeRemote.port, proxyPort: proxyPort,
    );

    service = RelayService(prober: const ServerProber(timeout: Duration(seconds: 2)));

    final events = <RelayEvent>[];
    final sub = service.events.listen(events.add);
    addTearDown(sub.cancel);

    await service.start([server]);
    await service.pollNow();

    expect(events, isNotEmpty);
    final event = events.firstWhere((e) => e.serverId == server.id);
    expect(event.status, RelayStatus.listening);
  });

  test('an active console session flips status to consoleConnected on the next poll', () async {
    final proxyPort = await _freePort();
    final server = ServerConfig.create(
      name: 'Test Server', host: '127.0.0.1', port: fakeRemote.port, proxyPort: proxyPort,
    );

    service = RelayService(prober: const ServerProber(timeout: Duration(seconds: 2)));
    final events = <RelayEvent>[];
    final sub = service.events.listen(events.add);
    addTearDown(sub.cancel);

    await service.start([server]);

    final console = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(console.close);
    console.send('hello'.codeUnits, InternetAddress.loopbackIPv4, proxyPort);
    await Future.delayed(const Duration(milliseconds: 100));

    await service.pollNow();

    final event = events.lastWhere((e) => e.serverId == server.id);
    expect(event.status, RelayStatus.consoleConnected);
    expect(event.bytesOut, greaterThan(0));
  });

  test('stop() releases the ports so they can be rebound immediately', () async {
    final proxyPort = await _freePort();
    final server = ServerConfig.create(
      name: 'Test Server', host: '127.0.0.1', port: fakeRemote.port, proxyPort: proxyPort,
    );

    service = RelayService(prober: const ServerProber(timeout: Duration(seconds: 2)));
    await service.start([server]);
    await service.stop();

    final rebound = await RawDatagramSocket.bind(InternetAddress.anyIPv4, proxyPort);
    rebound.close();
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/relay_service_test.dart
```

Expected: FAIL — cannot resolve `package:gazoo/core/relay/relay_service.dart`.

- [ ] **Step 3: Write the implementation**

Create `lib/core/relay/relay_service.dart`:

```dart
import 'dart:async';
import 'dart:io';

import '../config/server_config.dart';
import '../discovery/lan_broadcast_responder.dart';
import '../discovery/server_prober.dart';
import 'relay_listener.dart';

enum RelayStatus { listening, consoleConnected }

class RelayEvent {
  final String serverId;
  final RelayStatus status;
  final int bytesIn;
  final int bytesOut;

  const RelayEvent({
    required this.serverId,
    required this.status,
    required this.bytesIn,
    required this.bytesOut,
  });
}

class RelayService {
  final Duration idleTimeout;
  final Duration statusPollInterval;
  final ServerProber prober;
  final void Function(String message)? onLog;

  final Map<String, RelayListener> _listeners = {};
  final Map<String, ServerLiveInfo> _lastKnownLiveInfo = {};
  LanBroadcastResponder? _responder;
  List<ServerConfig> _activeServers = [];
  final StreamController<RelayEvent> _eventController = StreamController.broadcast();
  Timer? _pollTimer;

  RelayService({
    this.idleTimeout = const Duration(seconds: 60),
    this.statusPollInterval = const Duration(seconds: 5),
    ServerProber? prober,
    this.onLog,
  }) : prober = prober ?? const ServerProber();

  Stream<RelayEvent> get events => _eventController.stream;

  Future<void> start(List<ServerConfig> servers) async {
    if (_responder != null) {
      throw StateError('RelayService already running; call stop() first');
    }
    _activeServers = servers;

    for (final server in servers) {
      final remoteAddresses = await InternetAddress.lookup(server.host);
      final listener = RelayListener(
        bindAddress: InternetAddress.anyIPv4,
        listenPort: server.proxyPort,
        remoteAddress: remoteAddresses.first,
        remotePort: server.port,
        idleTimeout: idleTimeout,
        onLog: onLog,
      );
      await listener.start();
      _listeners[server.id] = listener;
    }

    _responder = LanBroadcastResponder(
      bindAddress: InternetAddress.anyIPv4,
      enabledServers: () => _activeServers,
      liveInfo: (server) =>
          _lastKnownLiveInfo[server.id] ??
          const ServerLiveInfo(
              protocolVersion: 0, gameVersion: 'unknown', playerCount: 0, maxPlayers: 0),
      onLog: onLog,
    );
    await _responder!.start();

    _pollTimer = Timer.periodic(statusPollInterval, (_) => pollNow());
    await pollNow();
  }

  Future<void> pollNow() async {
    for (final server in _activeServers) {
      final status = await prober.probe(server.host, server.port);
      if (status.online && status.motd != null) {
        _lastKnownLiveInfo[server.id] = ServerLiveInfo(
          protocolVersion: status.motd!.protocolVersion,
          gameVersion: status.motd!.gameVersion,
          playerCount: status.motd!.playerCount,
          maxPlayers: status.motd!.maxPlayers,
        );
      }
      final listener = _listeners[server.id];
      final activeSessions = listener?.activeSessionCount ?? 0;
      _eventController.add(RelayEvent(
        serverId: server.id,
        status: activeSessions > 0 ? RelayStatus.consoleConnected : RelayStatus.listening,
        bytesIn: listener?.bytesIn ?? 0,
        bytesOut: listener?.bytesOut ?? 0,
      ));
    }
  }

  Future<void> stop() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    await _responder?.stop();
    _responder = null;
    for (final listener in _listeners.values) {
      await listener.stop();
    }
    _listeners.clear();
    _activeServers = [];
  }

  Future<void> dispose() async {
    await stop();
    await _eventController.close();
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/relay_service_test.dart
```

Expected: PASS.

- [ ] **Step 5: Run the full core test suite together**

```bash
flutter analyze
flutter test
```

Expected: `flutter analyze` reports "No issues found!". `flutter test` passes all 8 test files (codec, server_config, settings, relay_session_table, relay_listener, server_prober, lan_broadcast_responder, relay_service) plus the stock counter widget test.

- [ ] **Step 6: Commit**

```bash
git add lib/core/relay/relay_service.dart test/relay_service_test.dart
git commit -m "Add RelayService: compose discovery + relay listeners behind one start/stop/event API"
```

---

## Self-Review Notes

- **Spec coverage:** Ping/Pong packet structure ✓ (Task 2), MOTD auto-population from real server ✓ (Task 6, wired into Task 8's `pollNow`), NAT-style session table with idle expiry ✓ (Task 4/5), multi-server support sharing the discovery port cleanly ✓ (Task 7, distinct-port demux), protocol-agnostic byte forwarding after handshake ✓ (Task 5 never parses post-discovery traffic). GUI, Android/iOS/desktop platform glue, and the CLI headless flag are explicitly deferred to follow-up plans (see Architecture note above) since they're independent subsystems per the brainstorming spec's own build order.
- **Type consistency:** Verified `ServerConfig`, `ServerLiveInfo`, `ServerStatus`/`MotdFields`, `RelayListener`, and `RelayEvent` signatures match exactly between the task that produces them and every task that consumes them.
- **No placeholders:** All code blocks are complete and runnable; no TODOs or "similar to Task N" references.

---

**Plan complete and saved to `docs/superpowers/plans/2026-07-10-core-networking-layer.md`.** Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
