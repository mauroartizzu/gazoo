# Contributing to Gazoo

Thanks for your interest! Gazoo is a small, focused project — a free,
ad-free way to make remote Minecraft Bedrock servers joinable from
consoles. Contributions that keep it small, focused, and free are very
welcome.

## Ground rules

- **No ads, no telemetry, no analytics — ever.** PRs adding any form of
  tracking, ads, or "phone home" behavior will be closed.
- **Keep the core headless.** Nothing under `lib/core/` may import
  `package:flutter`. The core must stay runnable and testable without a UI
  (that's what makes the headless CLI and future platform work possible).
- **Tests come with the change.** Every behavior change needs a test.
  The core layer is tested with real loopback UDP sockets (no mocks);
  UI state and widgets are tested with fakes injected via Provider.

## Getting started

```bash
git clone https://github.com/mauroartizzu/gazoo.git
cd gazoo
flutter pub get
flutter test        # should be fully green before and after your change
flutter analyze     # should report "No issues found!"
flutter run -d macos   # or windows / linux
```

## Project layout

| Path | What it is |
|---|---|
| `lib/core/raknet/` | RakNet Unconnected Ping/Pong packet codec |
| `lib/core/relay/` | Session table, UDP proxy, top-level `RelayService` |
| `lib/core/discovery/` | Server status prober + LAN broadcast responder |
| `lib/core/config/` | `ServerConfig` / `Settings` models |
| `lib/ui/state/` | `ChangeNotifier`s (no widget code) |
| `lib/ui/screens/` | The four screens |
| `lib/cli/` | Headless mode |
| `test/` | Mirrors the lib structure |

## Submitting changes

1. Fork, branch from `main`, make your change.
2. Run `flutter analyze` and `flutter test` — both must be clean.
3. Open a PR describing **what problem you hit** (not just what you
   changed). Small, single-purpose PRs are reviewed fastest.

Every push to `main` triggers the release workflow (tests → multi-platform
builds → GitHub Release), so `main` is expected to always be releasable.

## Release signing (maintainers)

- **Android**: release builds are signed when `android/key.properties`
  exists (gitignored), pointing at a keystore kept **outside** the repo:

  ```properties
  storePassword=...
  keyPassword=...
  keyAlias=gazoo
  storeFile=/absolute/path/to/gazoo-release.jks
  ```

  Without it, release builds fall back to debug signing so fresh clones
  and CI still build. Never commit a keystore or its passwords.
- **iOS**: automatic signing with the development team configured in the
  Xcode project. Building for a real device requires being signed into
  that Apple Developer account in Xcode.

## Reporting bugs

Use the bug report issue template. The most useful thing you can include
is the in-app log (Settings → Show log panel — the text is selectable) and
what network setup you have (same Wi-Fi? console type? server host?).
