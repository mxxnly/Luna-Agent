# Architecture

## Components

| Component | Role |
|-----------|------|
| **Daemon** (`cmd/agent`) | Enroll, heartbeat, command poll, WireGuard apply/up/down, metrics |
| **Menu bar** (`macos/`) | Status, local connect/disconnect, enroll UI, copy Device ID |
| **Control Server** | External HTTPS API (any implementation of Control API v1) |

```
┌──────────────────────────────┐
│  LunaAgent.app / menu bar    │
│         ↕ localhost IPC      │
│  lunaagentd (daemon)         │
│    ├─ WireGuard              │
│    └─ HTTPS Control API      │
└──────────────┬───────────────┘
               │ (internet, VPN independent)
               ▼
        Control Server URL
```

## Design constraints

1. **Control plane ≠ VPN path** — enroll, heartbeat, and commands must work while the tunnel is down.
2. **Configurable server** — end users / IT set the Control Server base URL at enroll time.
3. **Panel owns WireGuard keys** — agent applies a full `.conf` pushed via API; on apply failure it rolls back to the previous conf.
4. **Observe-only metrics** — CPU, RAM, disk, top processes; no process kill in MVP.

## Milestones

| ID | Scope |
|----|--------|
| M1 | Enroll, heartbeat (device), menu bar, launchd |
| M2 | Local WireGuard up/down, conf on disk, backup helpers |
| M3 | Signed remote commands, apply conf, revoke/rotate, desired_state |
| M4 | Metrics snapshot, minimal device UI on reference panel, signing/notarization prep |

See [security.md](security.md) for threat-oriented rules.
