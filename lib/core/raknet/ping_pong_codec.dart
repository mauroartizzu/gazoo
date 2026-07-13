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

/// Replaces the MOTD field delimiter (`;`) and newlines with a space so a
/// user-supplied name can never shift the fixed-position fields that follow
/// it in the `;`-delimited MOTD string.
String _sanitizeMotdField(String s) {
  return s.replaceAll(';', ' ').replaceAll('\n', ' ');
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
  final safeServerName = _sanitizeMotdField(serverName);
  final safeWorldName = _sanitizeMotdField(worldName);
  return 'MCPE;$safeServerName;$protocolVersion;$gameVersion;$playerCount;$maxPlayers;'
      '$serverGuid;$safeWorldName;$gamemode;1;$portIpv4;$portIpv6;';
}

MotdFields _motdFieldsFrom(List<String> parts) {
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
}

MotdFields parseMotd(String motd) {
  final parts = motd.split(';');
  if (parts.length < 12 || parts[0] != 'MCPE') {
    throw MalformedPacketException('Unrecognized MOTD format: $motd');
  }
  try {
    return _motdFieldsFrom(parts);
  } on FormatException catch (e) {
    // A remote server whose own name contains embedded ';' shifts every
    // field after it. If there are more parts than expected, assume the
    // extra ones belong to the name field, rejoin them, and retry once.
    if (parts.length > 13) {
      final extra = parts.length - 13;
      final recovered = <String>[
        parts[0],
        parts.sublist(1, 2 + extra).join(';'),
        ...parts.sublist(2 + extra),
      ];
      try {
        return _motdFieldsFrom(recovered);
      } on FormatException {
        throw MalformedPacketException('Unrecognized MOTD format: $motd ($e)');
      }
    }
    throw MalformedPacketException('Unrecognized MOTD format: $motd ($e)');
  }
}
