# ADR 0001: Tech stack

## Status

Accepted

## Context

LunaAgent needs a macOS client (menu bar + daemon), WireGuard control, HTTPS Control API client, and a path to notarized releases. The product must work with any Control Server that implements Control API v1.

## Decision

| Layer | Choice |
|-------|--------|
| Menu bar | SwiftUI full UI on macOS 13+; AppKit basic UI on macOS 10.14–12 |
| Daemon | Go 1.22+, module `github.com/mxxnly/Luna-Agent` |
| IPC | Unix domain socket + JSON + auth cookie |
| Autostart | LaunchAgent (user session) for MVP |
| Secrets | macOS Keychain; file-backed store in `LUNA_TEST_MODE=1` |
| HTTP | `net/http`, system trust store, HTTPS only |
| Command auth | Ed25519 signatures on control-plane commands |
| WireGuard | userspace `wireguard-go` + on-disk conf (`0600`); `LUNA_WG_DRY_RUN=1` in CI |
| Metrics | gopsutil-style collectors (CPU/RAM/disk + top processes) |
| Reference panel | `vpn-control-panel` Django `/api/v1/agent/*` |
| Local mock | `cmd/mockcontrol` for CI/e2e |

## Consequences

- Network Extension is deferred; TUN privileges need a helper path in M2+.
- Universal Darwin binaries (arm64 + amd64) via `lipo` from day one.
- Control plane traffic must work while the VPN tunnel is down.

## Superseding notes (dual installers)

- **macOS 13+:** autostart via `SMAppService` (mainApp + agent + daemon); Go binaries and WG tools live inside `LunaAgent.app`.
- **macOS 10.14–12:** reduced AppKit UI; classic LaunchAgents/Daemon still point at binaries **inside** the app (Legacy pkg + postinstall).
- See [architecture.md](../architecture.md) and [packaging.md](../packaging.md).
