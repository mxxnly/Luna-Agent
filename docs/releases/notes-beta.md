# LunaAgent $VERSION (Beta)

Pre-release for the `0.x` line. APIs and packaging may still change before 1.0.0.

## What's new in $VERSION

- Panel Update: if the WireGuard helper is offline, install it once (or elevate installer) so `agent_update` no longer fails with install_failed.
- Autostart: Login Agents installed once; menu bar returns after reboot without Background Items spam.
- Setup / installer text / Sonoma app icon fixes from 0.2.15–0.2.16.

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
