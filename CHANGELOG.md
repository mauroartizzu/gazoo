# Changelog

All notable changes to Gazoo are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Release tags follow the pattern `v<version>-<build>` (e.g. `v1.0.0+1-1`), where the
build number comes from the CI run that produced the release.

## [Unreleased]

### Added
- **Android foreground service + multicast lock** — the relay now keeps
  running while the app is backgrounded, with a persistent notification,
  and holds a Wi-Fi multicast lock so the console's discovery broadcasts
  keep arriving. Wired through a new platform hook (`RelayPlatform`) that
  is a no-op on all other platforms.
- **Android release signing** — release builds are now signed with a real
  release keystore when `android/key.properties` is present (falls back to
  debug signing otherwise, so fresh clones still build), both locally and
  in CI via encrypted secrets.

### Fixed
- Server names containing `;` no longer corrupt the advertised LAN MOTD
  (sanitized on build, recovered on parse, rejected in the add/edit form).
- A failed relay start (e.g. port already in use) now rolls back cleanly
  instead of leaving the app stuck on "Starting…" — and no longer persists
  the broken server as the auto-start target.
- Socket-level errors (Wi-Fi drop, sleep/wake) are now logged and handled
  on all listeners instead of becoming unhandled async errors.
- Double-tapping a server tile can no longer open two relay screens and
  tear down the active relay.
- Headless CLI now validates port ranges (1–65535) and rejects proxy port
  19132 (reserved for discovery), matching the GUI's validation.

## [1.0.0] - 2026-07-13

First public release.

### Added
- **Core relay engine** — RakNet Unconnected Ping/Pong LAN discovery,
  NAT-style session table, transparent per-server UDP proxy, real-server
  status prober, and a multi-server broadcast responder that demuxes each
  saved server onto its own dedicated proxy port.
- **Desktop GUI** — server list with add/edit/delete and live status
  (online/offline, ping, player count), active-relay screen with LAN IP and
  live byte counters, settings (idle timeout, auto-start last server,
  dark/light theme, log panel), and first-run onboarding with
  platform-specific setup notes.
- **Headless CLI mode** — `gazoo --headless --server=host:port
  [--name=...] [--proxy-port=...]` runs the relay with no GUI.
- **In-app log panel** — selectable/copyable log of discovery and relay
  activity, toggleable in Settings.
- **Release automation** — CI builds for Windows, macOS, Linux, Android
  (debug APK), and iOS (unsigned) on every push to `main`, with SHA256
  checksums attached to each release.

### Platform notes
- Windows, macOS, and Linux are fully functional.
- Android/iOS builds are attached to releases for testing, but background
  execution glue (Android foreground service, iOS local-network fallback)
  is not yet implemented — keep the app in the foreground while playing.

[Unreleased]: https://github.com/mauroartizzu/gazoo/compare/v1.0.0+1-1...HEAD
[1.0.0]: https://github.com/mauroartizzu/gazoo/releases/tag/v1.0.0+1-1
