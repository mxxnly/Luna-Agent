# LunaAgent $VERSION (Beta)

Pre-release for the `0.x` line. APIs and packaging may still change before 1.0.0.

## What's new in $VERSION

- Setup: no false "Move to /Applications" on ad-hoc beta when the app is already installed.
- Installer Welcome/Read Me: UTF-8 + ASCII-safe text (no garbled dashes in Installer.app).
- App icon: baked macOS squircle with transparent corners; do not ship flat AppIcon.png next to .icns.
- VPN: one-time Mac password installs the WireGuard root helper as a LaunchDaemon; Connect/Disconnect then use the Unix socket without asking again (including after reboot).
- Update: after panel `install_pkg`, wghelper restarts the menu bar app and user agent so the new version shows immediately.
- VPN Connect/Disconnect no longer require the organization admin password and stay clickable while busy.
- Remote: permanent password via RustDesk.toml; helper in `~/Applications/LunaRemote.app` keeps Screen Recording across Remote off/on.
- Autostart: user LaunchAgents for menu bar and agent when SMApp Login Item does not stick on unsigned beta builds.

## Packages

| File | macOS |
|------|--------|
| `LunaAgent_13plus.pkg` | 13 Ventura and newer - full UI, SMAppService |
| `LunaAgent_Legacy_10.14.pkg` | 10.14-12 - reduced UI, classic launchd |

Verify downloads with the attached `.sha256` files before install. Prefer copying the `.pkg` to `/tmp` if Desktop/Downloads is TCC-blocked.

## Documentation

- [Install](https://github.com/mxxnly/Luna-Agent/blob/main/docs/install.md)
- [macOS 13+](https://github.com/mxxnly/Luna-Agent/blob/main/docs/install-13plus.md)
- [Legacy](https://github.com/mxxnly/Luna-Agent/blob/main/docs/install-legacy.md)
- [User guide](https://github.com/mxxnly/Luna-Agent/blob/main/docs/user-guide.md)
