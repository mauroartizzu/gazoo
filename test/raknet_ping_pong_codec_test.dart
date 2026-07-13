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

    test('buildMotd sanitizes ";" and newlines out of serverName and worldName', () {
      final motd = buildMotd(
        serverName: 'Evil;Server\nName',
        protocolVersion: 622,
        gameVersion: '1.21.0',
        playerCount: 1,
        maxPlayers: 5,
        serverGuid: 1,
        worldName: 'World;2\nName',
        gamemode: 'Survival',
        portIpv4: 19133,
        portIpv6: 19134,
      );
      expect(motd, 'MCPE;Evil Server Name;622;1.21.0;1;5;1;World 2 Name;Survival;1;19133;19134;');

      final parsed = parseMotd(motd);
      expect(parsed.serverName, 'Evil Server Name');
      expect(parsed.worldName, 'World 2 Name');
      expect(parsed.portIpv4, 19133);
      expect(parsed.portIpv6, 19134);
    });

    test('parseMotd recovers a name containing one embedded ";"', () {
      // A remote (non-Gazoo) server whose own MOTD encoder didn't sanitize.
      const motd = 'MCPE;My;Server;622;1.21.0;3;10;555;World;Survival;1;19133;19134;';
      final parsed = parseMotd(motd);
      expect(parsed.serverName, 'My;Server');
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

    test('parseMotd recovers a name containing two embedded ";"', () {
      const motd = 'MCPE;My;;Server;622;1.21.0;3;10;555;World;Survival;1;19133;19134;';
      final parsed = parseMotd(motd);
      expect(parsed.serverName, 'My;;Server');
      expect(parsed.protocolVersion, 622);
      expect(parsed.worldName, 'World');
      expect(parsed.portIpv4, 19133);
      expect(parsed.portIpv6, 19134);
    });

    test('parseMotd still throws on a genuinely malformed MOTD with extra parts', () {
      // Extra parts present (so recovery is attempted), but the numeric
      // fields are non-numeric garbage even after recovery.
      const motd = 'MCPE;My;Server;notanumber;1.21.0;3;10;555;World;Survival;1;19133;19134;';
      expect(() => parseMotd(motd), throwsA(isA<MalformedPacketException>()));
    });
  });
}
