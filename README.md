# LunaAgent

macOS agent for organization-managed secure access.

LunaAgent runs in the menu bar, maintains a WireGuard tunnel (userspace), reports device and load telemetry to a configurable **Control Server**, and applies remote commands over HTTPS — including when the VPN tunnel is down.

Any control plane that implements **Control API v1** can manage LunaAgent. Reference implementation: `vpn-control-panel` (`/api/v1/agent/*`).

[![GitHub release](https://img.shields.io/github/v/release/mxxnly/Luna-Agent?include_prereleases)](https://github.com/mxxnly/Luna-Agent/releases)

> **Versioning:** `0.x.y` builds are **beta** (GitHub Pre-release). `1.0.0+` is **stable**. See [docs/releasing.md](docs/releasing.md).

## Install (end users / IT)

Download the dual packages from [Releases](https://github.com/mxxnly/Luna-Agent/releases):

| Package | macOS |
|---------|--------|
| **LunaAgent_13plus.pkg** | 13 Ventura and newer (full UI, SMAppService) |
| **LunaAgent_Legacy_10.14.pkg** | 10.14–12 only (reduced UI) |

Quick steps: [docs/install.md](docs/install.md). Prefer copying the `.pkg` to `/tmp` before `installer` if Desktop is blocked by TCC.

## Features

- WireGuard connect / disconnect (menu bar + remote API; `LUNA_WG_DRY_RUN=1` for CI)
- Device inventory heartbeat and signed remote commands (Ed25519)
- Push full WireGuard `.conf` with backup / rollback
- CPU / RAM / disk snapshot and top processes (observe-only; full charts on macOS 13+)
- Device token in Keychain; revoke / rotate via Control API

## Documentation

| Doc | Description |
|-----|-------------|
| [Install overview](docs/install.md) | Which pkg, verify sha256, first launch |
| [macOS 13+](docs/install-13plus.md) | SMAppService, Trash uninstall |
| [Legacy 10.14–12](docs/install-legacy.md) | LaunchAgents/Daemon, residual plists |
| [User guide](docs/user-guide.md) | Enroll, VPN, WG conf, Device ID |
| [Architecture](docs/architecture.md) | Components, IPC, control plane |
| [Packaging](docs/packaging.md) | Bundle layout, `make installer` |
| [Releasing](docs/releasing.md) | Beta vs stable, GitHub Releases |
| [Development](docs/development.md) | Local build and test |
| [Security](docs/security.md) / [SECURITY.md](SECURITY.md) | Reporting and hard rules |
| [Control API](api/openapi.yaml) | OpenAPI v1 |
| [ADRs](docs/adr/) | Tech stack and build decisions |

## Build (developers)

```bash
make ci                 # lint + tests + universal Go binaries
make e2e                # mockcontrol enroll/heartbeat
make installer          # both pkgs → ~/Desktop/LunaAgent/<VERSION>/
# VERSION=0.0.2 make installer
make publish-release    # upload Desktop folder to GitHub Releases (gh auth required)
```

Default `VERSION` is `0.0.1` (beta). See [docs/packaging.md](docs/packaging.md).

## Requirements

- **Runtime:** macOS 10.14+ (use the matching pkg channel)
- **Build:** Go 1.22+, Swift 5.9+, macOS SDK / Xcode CLT
- Control Server with HTTPS (or `mockcontrol` for local)

## License

[MIT](LICENSE) — Copyright (c) 2026 mxxnly
