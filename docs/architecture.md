# Architecture

## Components

| Component | Role |
|-----------|------|
| **Menu bar** (`macos/MenuBar`) | Status, enroll, connect/disconnect, WG conf; SwiftUI on 13+, AppKit basic on 10.14–12 |
| **Daemon** (`cmd/agent` → `lunaagentd`) | Enroll, heartbeat, command poll, WireGuard apply/up/down, metrics |
| **Helper** (`cmd/wghelper` → `luna-wghelper`) | Root: `wg-quick` / wireguard-go via `/var/run/luna-wg.sock` |
| **Bundled tools** (`Contents/Resources/luna-wg`) | bash 4+, wg, wg-quick, wireguard-go |
| **mockcontrol** | Local Control API for CI/e2e |
| **Control Server** | External HTTPS API (Control API v1); reference: vpn-control-panel |

```
┌─────────────────────────────────────────────┐
│  /Applications/LunaAgent.app                │
│  MacOS/LunaAgent  ↔  IPC sock  ↔  lunaagentd │
│                              ↕               │
│                         luna-wghelper (root) │
│                              ↕               │
│                    Resources/luna-wg tools   │
└──────────────────────┬──────────────────────┘
                       │ HTTPS (VPN-independent)
                       ▼
                 Control Server URL
```

## Lifecycle by channel

| | macOS 13+ pkg | Legacy 10.14–12 pkg |
|--|---------------|---------------------|
| Autostart UI | `SMAppService.mainApp` | LaunchAgent → app binary |
| User daemon | `SMAppService.agent` + embedded plist | `/Library/LaunchAgents` → `Contents/MacOS/lunaagentd` |
| Root helper | `SMAppService.daemon` + embedded plist | `/Library/LaunchDaemons` + postinstall |
| Min OS in Info.plist | 13.0 | 10.14 |

Tool discovery prefers paths relative to the executable inside the app bundle (`internal/bundlepath`).

## Tech stack

See [adr/0001-tech-stack.md](adr/0001-tech-stack.md).

## Build and release

See [adr/0002-build-and-test.md](adr/0002-build-and-test.md), [packaging.md](packaging.md), [releasing.md](releasing.md).

| Gate | Command |
|------|---------|
| Unit + lint + Go universal build | `make ci` |
| E2E (dry-run WG) | `make e2e` |
| Dual pkgs to Desktop | `make installer` |
| GitHub Release upload | `make publish-release` |

## Design constraints

1. **Control plane ≠ VPN path** — enroll, heartbeat, and commands work while the tunnel is down.
2. **Configurable server** — Control Server base URL at enroll time.
3. **Panel owns WireGuard material** — agent applies full `.conf`; rollback on failure.
4. **Observe-only metrics** — no remote process kill in product scope.
5. **No secrets in logs** — PrivateKey, PSK, device_token, enroll codes redacted.
6. **No Network Extension** in current product — userspace wireguard-go + root helper.
