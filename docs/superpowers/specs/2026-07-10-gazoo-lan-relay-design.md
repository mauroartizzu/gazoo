# Gazoo: Cross-Platform Minecraft Bedrock LAN Relay — Design

## Goal

A single-codebase Flutter app (Windows, macOS, Linux, iOS, Android) that makes a remote
Minecraft: Bedrock Edition server appear as a fake "LAN game" to consoles (Xbox, PlayStation)
on the local network, and transparently proxies all UDP traffic between the console and the
real remote server. Reimplements the discovery trick from `jhead/phantom` (Go, CLI-only) with
a GUI and mobile support.

No ads, no telemetry, no third-party SDKs beyond what networking/UI strictly requires.

## Tech Stack

**Flutter/Dart**, single codebase for all five targets. `dart:io`'s `RawDatagramSocket` covers
UDP unicast/broadcast on every target without a separate native networking core. State
management: **Provider + ChangeNotifier** — minimal boilerplate, and the core stays UI-free so
it can be unit-tested headless.

## Core Problem: Demuxing Multiple Advertised Servers on One Discovery Port

The console's RakNet LAN broadcast always targets UDP `19132`. If Gazoo advertises several
saved remote servers simultaneously, a single shared listener on `19132` cannot tell, from the
console's *next* handshake packet alone, which advertised server the console picked — RakNet's
connection packets carry no server-selection payload.

**Resolution:** the Unconnected Pong's MOTD string carries a `<Port IPv4>` field that need not
equal `19132`. So:

- One shared `LanBroadcastResponder` binds `19132` (and `19133` for IPv6). On every
  Unconnected Ping it replies with **one Unconnected Pong per enabled saved server**, each
  carrying a distinct `Server GUID` and a distinct **dedicated proxy port** assigned to that
  server's config (e.g. `19133 + n`).
- Each enabled server gets its own `RelayListener` bound to that dedicated port — a plain
  transparent UDP proxy. No RakNet packet parsing beyond the initial ping/pong handshake is
  needed; everything after that is byte-for-byte forwarding.
- Net effect: the console sees N distinct LAN entries; whichever it joins lands on a port that
  unambiguously maps to exactly one real server, with zero packet inspection required.

## Layering

```
lib/
  core/                          # pure Dart, no Flutter/UI imports — unit-testable headless
    raknet/
      ping_pong_codec.dart       # Unconnected Ping/Pong encode+decode (pure functions)
    discovery/
      server_prober.dart         # pings the real remote server, parses its live Pong
                                  # (player count, max players, game version, MOTD)
      lan_broadcast_responder.dart  # owns the 19132/19133 sockets, answers console pings
    relay/
      session.dart               # one client<->server UDP pairing + idle-expiry timer
      session_table.dart         # NAT map keyed by (clientIp, clientPort)
      relay_listener.dart        # owns one dedicated per-server proxy port
      relay_service.dart         # composes the above; exposes status/byte-count stream
    config/
      server_config.dart         # saved server model: name, host, port, guid, proxy port
      settings.dart              # timeout, auto-start, theme, log toggle
  ui/
    screens/                     # ServerList, ActiveRelay, Settings, Onboarding
    widgets/
    theme/
    state/                       # ChangeNotifier adapters wrapping core services for Provider
  platform/
    android/                     # foreground service + MulticastLock glue (platform channel)
    ios/                         # Info.plist config; NWListener/NWConnection fallback if needed
    desktop/                     # firewall-rule detection/instructions (Windows/macOS/Linux)
  cli/
    headless_runner.dart         # `--headless --server=ip:port` entry, drives RelayService directly
  main.dart
test/
  raknet_ping_pong_codec_test.dart
  relay_session_table_test.dart
  relay_listener_test.dart
  server_prober_test.dart
```

`RelayService` never imports Flutter. The UI's `state/` layer wraps it in `ChangeNotifier`s.
The future headless CLI mode is a thin wrapper over the same `RelayService` — proving the
core/UI boundary is real, not just theoretical.

## RakNet Packet Details (from spec, authoritative)

**Unconnected Ping** (console → Gazoo, port 19132):
`0x01` (1B id) + ping time (8B int64) + magic (16B: `00 ff ff 00 fe fe fe fe fd fd fd fd 12 34 56 78`) + client GUID (8B int64)

**Unconnected Pong** (Gazoo → console):
`0x1c` (1B id) + echoed ping time (8B) + server GUID (8B) + magic (16B, same) + MOTD length (2B BE short) + MOTD string:
`MCPE;<Name>;<Protocol>;<Version>;<Players>;<MaxPlayers>;<ServerGUID>;<World>;<Gamemode>;1;<PortIPv4>;<PortIPv6>;`

`server_prober.dart` sends a real Unconnected Ping to the configured remote server and parses
its real Pong to auto-populate player count/max players/game version in the advertised MOTD,
avoiding version-mismatch "connection failed" errors on the console.

## GUI Screens

1. **Server List** — add/edit/delete saved servers; live status per entry (online/offline,
   ping, player count) via `server_prober`.
2. **Active Relay** — start/stop; shows Listening/Console Connected/Idle state, detected LAN
   IP, byte in/out or activity pulse, Stop button.
3. **Settings** — idle timeout, auto-start last server, theme toggle, log panel toggle, and
   (mobile) a persistent "keep app open" reminder.
4. **Onboarding** — explains the same-LAN requirement and platform-specific setup (below).

## Platform-Specific Behavior

- **Android**: `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`, `INTERNET` permissions;
  relay runs as a foreground service with a persistent notification; `WifiManager.MulticastLock`
  held while active, released on stop.
- **iOS**: `NSLocalNetworkUsageDescription` in Info.plist; validate `dart:io` UDP
  broadcast/receive works under iOS sandboxing, falling back to a platform channel over
  `Network.framework` (`NWListener`/`NWConnection`) if it's blocked. UI surfaces a persistent
  "keep this app open while playing" banner — no false promise of background operation.
- **Windows/macOS/Linux**: first-run firewall guidance (Windows Defender prompt for
  private+public; macOS's own incoming-connection prompt; Linux `ufw`/`firewalld` commands for
  UDP `19132`). Headless CLI mode (`--headless --server=ip:port`) as a bonus, enabled by the
  core/UI split above.

## Error Handling

User-facing messages for: target server unreachable, local port already in use, socket bind
permission denied, no network interface found. Surfaced via the in-app log panel (toggleable
in Settings) in addition to screen-level state.

## Testing Strategy

Unit tests only, no widget/UI tests in the first milestone:
- `ping_pong_codec_test.dart`: encode/decode round-trip, malformed/truncated packet handling
- `relay_session_table_test.dart`: session creation, idle expiry, multi-session isolation
- `relay_listener_test.dart`: byte forwarding correctness with fake/loopback sockets
- `server_prober_test.dart`: real-pong parsing, timeout/unreachable handling

## Build Order

1. RakNet codec + `server_prober`, unit-tested in isolation
2. `session_table` + `relay_listener`, unit-tested with fake sockets
3. Wire `RelayService` + `LanBroadcastResponder` together (multi-server demux)
4. GUI screens on top, Provider bindings
5. Platform glue (Android foreground service/multicast lock, iOS entitlements, desktop
   firewall detection)
6. Headless CLI flag (bonus)

## Out of Scope (first milestone)

- Update-check network call (explicitly optional per spec; skip unless requested later)
- Full RakNet protocol implementation beyond ping/pong — everything past discovery is opaque
  byte forwarding by design
- Widget/UI automated tests (manual verification only, first pass)
