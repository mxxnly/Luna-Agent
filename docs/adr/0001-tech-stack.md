# ADR 0001: Tech stack

## Status

Accepted

## Context

LunaAgent needs a macOS client (menu bar + daemon), WireGuard control, HTTPS Control API client, and a path to notarized releases. The product must work with any Control Server that implements Control API v1.

## Decision

| Layer | Choice |
|-------|--------|
| Menu bar | Swift 5.9+ / SwiftUI (AppKit status item), macOS 13+ |
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
