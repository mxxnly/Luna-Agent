# LunaAgent

**Organization-managed WireGuard on macOS.**

LunaAgent is a menu-bar agent that enrolls devices into your control plane, maintains a userspace WireGuard tunnel, and applies signed remote commands — including while the tunnel is down. Inventory and load telemetry flow back over HTTPS so operators can see machines without guessing.

Any panel that implements **Control API v1** can drive LunaAgent. Reference control plane: `vpn-control-panel` (`/api/v1/agent/*`).

[![Release](https://img.shields.io/github/v/release/mxxnly/Luna-Agent?include_prereleases&label=release)](https://github.com/mxxnly/Luna-Agent/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> **Channels:** `0.x.y` = **beta** (GitHub Pre-release). `1.0.0+` = **stable** (Latest). Details in [docs/releasing.md](docs/releasing.md).

---

## Install

Download from [Releases](https://github.com/mxxnly/Luna-Agent/releases) — pick the package that matches the Mac:

| Package | macOS | Experience |
|---------|--------|------------|
| `LunaAgent_13plus.pkg` | 13 Ventura and newer | Full SwiftUI UI · SMAppService lifecycle |
| `LunaAgent_Legacy_10.14.pkg` | 10.14–12 only | Reduced AppKit UI · classic launchd |

Verify the SHA-256, copy the pkg to `/tmp` if Desktop/Downloads is TCC-blocked, then install. Full walkthrough: **[docs/install.md](docs/install.md)**.

---

## What it does

- **Connect / Disconnect** from the menu bar or the control plane
- **Enroll** with Control URL + code → device token in Keychain
- **Apply** full WireGuard configs with backup and rollback on failure
- **Remote desktop** via an embedded helper (no separate app on the Mac) over your relay
- **Heartbeat** device inventory; observe-only CPU / RAM / disk / top processes
- **Execute** Ed25519-signed, time-limited remote commands (no replay)
- **Ship** as a self-contained `.app` — daemon, root helper, WG tools, and remote helper inside the bundle

---

## Documentation

| Guide | Audience |
|-------|----------|
| [Install](docs/install.md) · [13+](docs/install-13plus.md) · [Legacy](docs/install-legacy.md) | IT / end users |
| [User guide](docs/user-guide.md) | Operators of enrolled Macs |
| [Remote desktop](docs/remote-desktop.md) | RustDesk session without VPN |
| [Architecture](docs/architecture.md) | Engineers integrating or extending |
| [Packaging](docs/packaging.md) · [Releasing](docs/releasing.md) | Maintainers shipping builds |
| [Development](docs/development.md) · [Contributing](CONTRIBUTING.md) | Contributors |
| [Security](docs/security.md) · [SECURITY.md](SECURITY.md) | Security review & disclosure |
| [Control API](api/openapi.yaml) · [ADRs](docs/adr/) | Protocol & design history |

---

## Build

```bash
make ci                       # lint, tests, universal Go binaries
make e2e                      # enroll/heartbeat against mockcontrol
VERSION=0.0.1 make installer  # dual pkgs → ~/Desktop/LunaAgent/<VERSION>/
VERSION=0.0.1 make publish-release
```

Requires Go 1.22+, Swift 5.9+, and a macOS SDK (Xcode or CLT). Runtime: macOS 10.14+ with the matching installer channel.

---

## License

[MIT](LICENSE) · Copyright © 2026 mxxnly
