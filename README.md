# LunaAgent

macOS agent for organization-managed secure access.

LunaAgent runs in the menu bar, maintains a WireGuard tunnel, reports device and load telemetry to a configurable **Control Server**, and applies remote commands (connect / disconnect / replace WireGuard config) over HTTPS — including when the VPN tunnel is down.

Any control plane that implements **Control API v1** can manage LunaAgent. A reference implementation may live alongside this repository in a separate control-panel project.

## Features (roadmap)

- WireGuard connect / disconnect (local menu bar + remote API)
- Device inventory heartbeat (hostname, model, serial, OS, agent version)
- Push full WireGuard `.conf` from the admin panel with backup / rollback
- CPU / RAM / disk snapshot and top processes (observe-only)
- Device token auth, signed commands, revoke / rotate

## Repository layout

```
LunaAgent/
├── api/           # Control API v1 (OpenAPI)
├── branding/      # App icons, menu bar marks, wordmarks
├── cmd/           # Agent daemon entrypoints
├── docs/          # Architecture and security notes
├── internal/      # Private packages (api client, wg, metrics, secure)
├── macos/         # Menu bar companion (Swift)
└── packaging/     # launchd, future .pkg
```

## Requirements

- macOS 13+
- A Control Server with a valid HTTPS certificate (enroll URL + one-time code)

## Quick start (development)

Implementation is starting at Milestone 1 (enroll + heartbeat + menu bar). Until the first binary ships, see:

- [docs/architecture.md](docs/architecture.md)
- [docs/security.md](docs/security.md)
- [api/openapi.yaml](api/openapi.yaml)

## Branding

Product assets live under [`branding/`](branding/). Palette and usage map: [`branding/BRAND.md`](branding/BRAND.md).

## Security

Do not open issues that include WireGuard private keys, device tokens, or live enroll codes. See [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
