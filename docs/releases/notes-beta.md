# LunaAgent $VERSION (Beta)

Pre-release for the `0.x` line. APIs and packaging may still change before 1.0.0.

## What's new in $VERSION

- Patch build to verify panel **Update** from 0.2.18 (install_pkg + restart).
- Panel Update works when the WireGuard helper was offline (EnsureRootHelper / elevated installer fallback).
- Autostart, setup, installer text, and Sonoma icon fixes from 0.2.15-0.2.18.

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
