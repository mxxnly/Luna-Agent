# LunaAgent $VERSION (Beta)

Pre-release for the `0.x` line. APIs and packaging may still change before 1.0.0.

## What’s new in $VERSION

- Installed agent version is shown in the menu bar app (header, Home, Device, About) and in tooltips.
- Control panel surfaces agent version as a dedicated badge and device stat (heartbeat still reports `agent_version`).
- Remote desktop: apply permanent password via macOS `--server` flow so panel session password is accepted.
- VPN: Disconnect clears desired state before Down and fails if the tunnel stays up; UI shows handshake/helper status.
- Home shows only whether VPN actually works; interface/handshake/helper details stay on the VPN tab (via root helper status).
- Remote: keep custom ID server after GUI open (fixes “device offline” when helper opened on public network).
- Remote: hard-timeout RustDesk CLI so poll/ack cannot hang; set password on --server before GUI.
- Remote: one GUI open (no -n), no CLI spam after GUI; never re-exec a command after success (ack retry only).
- Remote: keep --server alive after password set (killing it early left panel password unset).
- Remote: set permanent password via RustDesk.toml (embedded helper is not /Applications/RustDesk.app + root, so `--password` CLI never applied and panel still acked ok).
- Remote: install helper to `~/Applications/LunaRemote.app` and launch once (no dual --server); keeps Screen Recording across Remote off/on.
- Autostart: always install user LaunchAgents for menu bar (`com.lunaagent.ui`) and agent so reboot works when SMApp Login Item did not stick.
- VPN Connect/Disconnect no longer require the organization admin password (or stay disabled while busy).

## Packages

| File | macOS |
|------|--------|
| `LunaAgent_13plus.pkg` | 13 Ventura and newer — full UI, SMAppService |
| `LunaAgent_Legacy_10.14.pkg` | 10.14–12 — reduced UI, classic launchd |

Verify downloads with the attached `.sha256` files before install. Prefer copying the `.pkg` to `/tmp` if Desktop/Downloads is TCC-blocked.

## Documentation

- [Install](https://github.com/mxxnly/Luna-Agent/blob/main/docs/install.md)
- [macOS 13+](https://github.com/mxxnly/Luna-Agent/blob/main/docs/install-13plus.md)
- [Legacy](https://github.com/mxxnly/Luna-Agent/blob/main/docs/install-legacy.md)
- [User guide](https://github.com/mxxnly/Luna-Agent/blob/main/docs/user-guide.md)
