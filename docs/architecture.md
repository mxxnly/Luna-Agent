# Architecture

LunaAgent is a **self-contained macOS application** plus a privileged helper. The control plane is external; the tunnel is local userspace WireGuard.

## Components

| Component | Binary / path | Responsibility |
|-----------|---------------|----------------|
| Menu bar | `macos/MenuBar` → `LunaAgent` | Status, enroll, VPN controls, WG conf; SwiftUI on 13+, AppKit on 10.14–12 |
| Agent | `cmd/agent` → `lunaagentd` | Enroll, heartbeat, command poll, apply/up/down, metrics |
| Helper | `cmd/wghelper` → `luna-wghelper` | Root: `wg-quick` / wireguard-go via `/var/run/luna-wg.sock` |
| Bundled tools | `Contents/Resources/luna-wg` | `bash`, `wg`, `wg-quick`, `wireguard-go` |
| mockcontrol | `cmd/mockcontrol` | Local Control API for CI and e2e |
| Control Server | External HTTPS | Control API v1 (reference: `vpn-control-panel`) |

```text
┌──────────────────────────────────────────────────┐
│  /Applications/LunaAgent.app                     │
│                                                  │
│   LunaAgent  ←── IPC (UDS + cookie) ──→  lunaagentd
│                                          │       │
│                                          ▼       │
│                                    luna-wghelper │
│                                     (root)       │
│                                          │       │
│                                          ▼       │
│                              Resources/luna-wg   │
└──────────────────────┬───────────────────────────┘
                       │  HTTPS  (independent of tunnel)
                       ▼
                 Control Server
```

## Lifecycle by installer channel

| Concern | macOS 13+ | Legacy 10.14–12 |
|---------|-----------|-----------------|
| UI autostart | `SMAppService.mainApp` | LaunchAgent → app binary |
| User agent | `SMAppService.agent` + embedded plist | `/Library/LaunchAgents` → `Contents/MacOS/lunaagentd` |
| Root helper | `SMAppService.daemon` + embedded plist | `/Library/LaunchDaemons` + postinstall wrappers |
| `LSMinimumSystemVersion` | 13.0 | 10.14 |

Tool discovery resolves paths relative to the running executable inside the bundle (`internal/bundlepath`).

## Design constraints

1. **Control plane ≠ VPN path** — enroll, heartbeat, and commands must succeed while the tunnel is down.
2. **Configurable server** — Control Server base URL is chosen at enroll time.
3. **Panel owns WireGuard material** — the agent applies a full `.conf` and rolls back on failure.
4. **Observe-only metrics** — no remote process kill in product scope.
5. **No secrets in logs** — PrivateKey, PSK, device token, and enroll codes are redacted.
6. **No Network Extension (yet)** — userspace `wireguard-go` plus a root helper.

## Decision records and shipping

- Stack: [ADR 0001](adr/0001-tech-stack.md)
- Build / test: [ADR 0002](adr/0002-build-and-test.md)
- Packages: [packaging.md](packaging.md)
- Releases: [releasing.md](releasing.md)

| Gate | Command |
|------|---------|
| Lint + unit tests + universal Go build | `make ci` |
| E2E against mockcontrol (WG dry-run) | `make e2e` |
| Dual installers → Desktop | `make installer` |
| Publish GitHub Release | `make publish-release` |
