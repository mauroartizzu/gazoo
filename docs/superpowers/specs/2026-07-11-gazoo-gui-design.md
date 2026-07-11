# Gazoo: GUI Layer — Design

## Goal

Build the Flutter GUI on top of the already-implemented, fully-tested core networking layer (`lib/core/`: RakNet codec, config models, session/relay, discovery/prober, `RelayService`). This milestone adds the 4 screens from the original project spec — Server List, Active Relay, Settings, Onboarding — plus the state-management/persistence layer that connects them to the core.

This is milestone 2 of the Gazoo project (see `docs/superpowers/specs/2026-07-10-gazoo-lan-relay-design.md` for the overall architecture and `docs/superpowers/plans/2026-07-10-core-networking-layer.md` for the completed core layer). Platform-specific glue (Android foreground service/multicast lock, iOS entitlements, desktop firewall detection) and the headless CLI flag remain out of scope for this milestone — they depend on this GUI/state layer existing first and will each get their own spec/plan.

## State Layer

Three `ChangeNotifier`s wired at the app root via `MultiProvider`, plus a small log buffer:

- **`ServerListNotifier`** — holds the saved `List<ServerConfig>`. Persists as a JSON-encoded string via `shared_preferences` (key `saved_servers`). Provides `add`/`update`/`remove`. Independently polls each saved server's live status (online/offline, ping latency, player count) via `ServerProber` on a timer (default every 10s) — this runs regardless of whether a relay is active, since the Server List screen shows live status for servers that aren't currently relayed.
- **`RelayNotifier`** — wraps exactly one `RelayService` instance for the currently-active server (or none). Exposes `start(ServerConfig)` / `stop()`, and forwards `RelayService.events` into `notifyListeners()` so `Active Relay` can rebuild on every `RelayEvent`. Also exposes the detected LAN IP(s) via `NetworkInterface.list()` for display.
- **`SettingsNotifier`** — holds `Settings`, persists via `shared_preferences` (key `settings`, JSON-encoded). Requires one addition to the already-built `Settings` model (`lib/core/config/settings.dart`): a new `hasSeenOnboarding` bool field (default `false`), with `copyWith`/`toJson`/`fromJson` updated to match — this is a small, backward-compatible extension of Task 3's approved work, not a redesign.
- **`AppLog`** — a `ChangeNotifier` holding a bounded (200-line) `List<String>` ring buffer. `RelayService` and `ServerProber` instances constructed by the notifiers above are given `onLog: appLog.append`, so every core-layer log line surfaces in the in-app debug panel described in the original spec.

New dependencies: `provider` (^6.x) and `shared_preferences` (^2.x) — both standard, ad-free, telemetry-free Flutter ecosystem packages. No other third-party packages are added this milestone.

## Navigation

Confirmed via mockup: `NavigationBar` (width < 600) / `NavigationRail` (width ≥ 600, via a `LayoutBuilder` breakpoint) with two persistent destinations — **Servers** and **Settings**. Tapping a server in the list pushes **Active Relay** (a contextual detail screen, not a tab, since it only makes sense for one server at a time). **Onboarding** is a full-screen route shown before any other screen when `SettingsNotifier.settings.hasSeenOnboarding == false`; a "Get Started" button sets the flag and navigates to the normal Servers tab. Once dismissed, Onboarding remains reachable from Settings as a "Help" entry — same screen, no flag change on that path.

Routing uses plain `Navigator.push`/`pop` (named routes for the two top-level tabs, direct push for Active Relay and Onboarding) — no router package, since 4 screens plus one contextual detail don't justify one.

## Screens

1. **Server List** (`lib/ui/screens/server_list_screen.dart`) — `ListView` of server tiles (name, host:port, live status badge: online/offline/ping-ms/player-count from `ServerListNotifier`). Floating action button opens an add/edit form (a `Dialog` or full-screen form on narrow widths) for name/host/port; `ServerConfig.create`/`copyWith` handle id/guid assignment and proxy-port selection (auto-assigned sequentially starting at 19133, adjustable in the form). Swipe-to-delete or an overflow menu removes a server. Tapping a tile (outside the delete affordance) pushes Active Relay for that server.

2. **Active Relay** (`lib/ui/screens/active_relay_screen.dart`) — reads `RelayNotifier`. Shows current `RelayStatus` (Listening / Console Connected — "Idle" is represented as `RelayStatus.listening` with zero active sessions, matching the core's actual two-state enum), the detected LAN IP(s), a byte in/out counter with a brief pulse animation on each change, and a "Stop Relay" button that calls `RelayNotifier.stop()` and pops back to Server List. On mobile, a persistent banner reads "Keep this app open while playing" (per the original spec's iOS/Android background-limitation requirement — shown on all mobile platforms here since Android's foreground-service exemption is platform-glue work for a later milestone, not yet implemented).

3. **Settings** (`lib/ui/screens/settings_screen.dart`) — reads/writes `SettingsNotifier`. Idle timeout (a duration picker, minutes, min 10s/max 10min per `RelayService`'s configurable timeout), auto-start-last-used-server toggle, light/dark theme toggle, "show log panel" toggle (reveals `AppLog`'s buffer in a bottom sheet or expandable panel when on), and a "Help" entry that re-opens the Onboarding screen without touching `hasSeenOnboarding`.

4. **Onboarding** (`lib/ui/screens/onboarding_screen.dart`) — static explanatory content (same-LAN requirement) plus platform-specific setup notes (conditionally shown based on `Platform.isAndroid`/`isIOS`/desktop checks): Android permissions note, iOS local-network-prompt note, desktop firewall command hints (from the original spec's platform-specific requirements — text only this milestone, no actual permission requests or firewall detection, which are platform-glue work for a later milestone). Ends with a "Get Started" button.

## Theming

`lib/ui/theme/app_theme.dart` — light and dark `ThemeData` built from Material 3 (`useMaterial3: true`), switched by `SettingsNotifier.settings.darkMode`. No custom design system beyond Flutter's Material defaults — this app doesn't need brand styling.

## Testing

- **Notifier unit tests** (`test/ui/server_list_notifier_test.dart`, `test/ui/settings_notifier_test.dart`): persistence round-trip against a fake `SharedPreferences` (the package ships `SharedPreferences.setMockInitialValues` for exactly this), CRUD correctness, `RelayNotifier` event-forwarding correctness against a fake/stub `RelayService`-shaped stream (not a real `RelayService`, since this is a state-plumbing test, not a networking test — the real `RelayService` is already covered by Task 8's tests).
- **Settings model extension test**: extend the existing `test/settings_test.dart` for the new `hasSeenOnboarding` field (default `false`, round-trips through JSON) — this is a modification to Task 3's approved test file, not a new file.
- **Widget tests** (`test/ui/*_screen_test.dart`): one per screen, verifying key interactive elements render and respond (add-server dialog opens, stop-relay button calls `RelayNotifier.stop()`, theme toggle flips `ThemeData.brightness`) using `flutter_test`'s `WidgetTester` with mocked/fake notifiers injected via `Provider` overrides — not real sockets, since UI tests shouldn't depend on real networking (that's the core layer's job).

## Out of Scope (this milestone)

- Android foreground service + multicast lock (platform glue, later milestone)
- iOS `Network.framework` fallback / `NSLocalNetworkUsageDescription` wiring (platform glue, later milestone)
- Desktop firewall detection (platform glue, later milestone)
- Headless CLI flag (later milestone, decoupled core already supports it)
- Actual permission-request flows (Onboarding shows explanatory text only this milestone)
- A router package (plain `Navigator` is sufficient at this scale)

## Build Order

1. Extend `Settings` with `hasSeenOnboarding` (modifies Task 3's existing file + test)
2. `ServerListNotifier` + persistence, unit-tested
3. `SettingsNotifier` + persistence, unit-tested
4. `AppLog`, unit-tested
5. `RelayNotifier`, unit-tested against a fake event stream
6. `app_theme.dart` (light/dark `ThemeData`)
7. Server List screen + add/edit form, widget-tested
8. Active Relay screen, widget-tested
9. Settings screen, widget-tested
10. Onboarding screen + first-run routing wired into `main.dart`, widget-tested
11. Responsive nav shell (`NavigationBar`/`NavigationRail` breakpoint) wiring all screens together in `main.dart`
