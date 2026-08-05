# LunaAgent $VERSION (Beta)

Pre-release for the `0.x` line. APIs and packaging may still change before 1.0.0.

## What's new in $VERSION

- Fix panel Update restart loop: install no longer kills the agent before Ack; pending Update no longer re-runs forever.
- Skip reinstall when already on the target version (`already_current`).
- Panel Update helper-offline fallback from 0.2.18.

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
