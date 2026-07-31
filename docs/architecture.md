# Architecture

## Components

| Component | Role |
|-----------|------|
| **Daemon** (`cmd/agent`) | Enroll, heartbeat, command poll, WireGuard apply/up/down, metrics |
| **Menu bar** (`macos/MenuBar`) | Status, local connect/disconnect, enroll UI, copy Device ID |
| **mockcontrol** (`cmd/mockcontrol`) | Local Control API for CI/e2e |
| **Control Server** | External HTTPS API (Control API v1); reference: vpn-control-panel |

```
┌──────────────────────────────┐
│  LunaAgent.app / menu bar    │
│         ↕ Unix socket JSON   │
│  lunaagentd (daemon)         │
│    ├─ WireGuard (wireguard-go / dry-run)
│    └─ HTTPS Control API      │
└──────────────┬───────────────┘
               │ (internet, VPN independent)
               ▼
        Control Server URL
```

## Tech stack

See [adr/0001-tech-stack.md](adr/0001-tech-stack.md).

## Build and test matrix

See [adr/0002-build-and-test.md](adr/0002-build-and-test.md).

| Gate | When | Command |
|------|------|---------|
| Unit + lint + universal build | Every PR | `make ci` |
| Integration (mockcontrol) | Every PR | part of `make ci` |
| E2E script | main / release | `make e2e` |
| Notarized pkg + smoke | tag `v*` | `make package` + release workflow |

## Design constraints

1. **Control plane ≠ VPN path** — enroll, heartbeat, and commands must work while the tunnel is down.
2. **Configurable server** — IT sets the Control Server base URL at enroll time.
3. **Panel owns WireGuard keys** — agent applies a full `.conf`; on apply failure it rolls back.
4. **Observe-only metrics** — CPU, RAM, disk, top processes; no process kill in MVP.
5. **No secrets in logs** — PrivateKey, PSK, device_token, enroll codes are redacted.

## Milestones

| ID | Scope |
|----|--------|
| M1 | Enroll, heartbeat (device), menu bar, IPC, launchd, CI green |
| M2 | WireGuard conf apply/up/down, backup/rollback, dry-run for CI |
| M3 | Signed remote commands, reference Django API, e2e |
| M4 | Metrics snapshot, packaging/sign/notarize scripts, release-smoke |
