# LunaAgent

macOS agent for organization-managed secure access.

LunaAgent runs in the menu bar, maintains a WireGuard tunnel, reports device and load telemetry to a configurable **Control Server**, and applies remote commands (connect / disconnect / replace WireGuard config) over HTTPS — including when the VPN tunnel is down.

Any control plane that implements **Control API v1** can manage LunaAgent. Reference endpoints live in `vpn-control-panel` under `/api/v1/agent/*`.

## Features

- WireGuard connect / disconnect (local menu bar + remote API; `LUNA_WG_DRY_RUN=1` for CI)
- Device inventory heartbeat
- Push full WireGuard `.conf` with backup / rollback
- CPU / RAM / disk snapshot and top processes (observe-only)
- Device token auth, signed commands (Ed25519), revoke / rotate

## Build & test

```bash
make ci          # lint + unit/integration tests + universal darwin binary
make e2e         # mockcontrol + enroll/heartbeat once
make build-app   # SwiftUI/AppKit menu bar .app
make package     # .pkg (unsigned unless certs configured)
make sign        # Developer ID (optional env)
make notarize    # notarytool (optional env)
make release-smoke
```

See [docs/adr/0001-tech-stack.md](docs/adr/0001-tech-stack.md) and [docs/adr/0002-build-and-test.md](docs/adr/0002-build-and-test.md).

## Repository layout

```
LunaAgent/
├── api/           # Control API v1 (OpenAPI)
├── branding/      # App icons, menu bar marks, wordmarks
├── cmd/agent      # lunaagentd
├── cmd/mockcontrol
├── docs/          # Architecture + ADRs
├── internal/      # api, agent, wg, crypto, metrics, …
├── macos/MenuBar  # Swift menu bar
└── packaging/     # launchd, scripts
```

## Requirements

- macOS 13+
- Go 1.22+
- Swift 5.9+ (menu bar)
- Control Server with HTTPS (or `mockcontrol` for local)

## Security

Do not open issues that include WireGuard private keys, device tokens, or live enroll codes. See [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
