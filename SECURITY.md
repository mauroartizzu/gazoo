# Security Policy

## Supported versions

Only the [latest release](https://github.com/mauroartizzu/gazoo/releases/latest)
is supported. Gazoo has no auto-update mechanism, so please check that
you're on the newest build before reporting.

## What Gazoo does on the network

For transparency, the complete list of network activity Gazoo performs:

- Listens on UDP `19132` (LAN discovery) and one dedicated UDP port per
  configured server (the relay itself).
- Sends RakNet status pings to the servers **you** configure, and relays
  console traffic to them, byte for byte.
- Nothing else. No update checks, no telemetry, no third-party endpoints.

## Reporting a vulnerability

Please **do not** open a public issue for security problems. Instead, use
GitHub's [private vulnerability reporting](https://github.com/mauroartizzu/gazoo/security/advisories/new)
for this repository.

You can expect an acknowledgment within a week. Since this is a spare-time
project there is no bug bounty, but reporters are credited in the release
notes of the fix (unless you prefer otherwise).

## Scope notes

- Gazoo is a transparent UDP relay: it intentionally forwards whatever the
  console and server exchange, without inspecting it. Vulnerabilities in
  Minecraft itself or in the remote server are out of scope.
- The relay listens on your local network. Running it on a hostile LAN is
  not a supported threat model — it's designed for home networks.
