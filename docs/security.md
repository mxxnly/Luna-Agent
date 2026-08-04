# Security

## Trust model

| Party | Trust assumption |
|-------|------------------|
| **Control Server** | Trusted after enroll (HTTPS + command-signing public key delivered at enroll). |
| **Device token** | Authenticates the agent; lives in the macOS Keychain (file store only under `LUNA_TEST_MODE=1`). |
| **Panel operators** | Can push WireGuard configs and toggle the tunnel — treat admin access as highly privileged. |
| **WireGuard helper** | Runs as root (SMAppService daemon or legacy LaunchDaemon); peers must pass Unix-socket credential checks on `/var/run/luna-wg.sock`. |

## Secrets

| Secret | Storage | Wire |
|--------|---------|------|
| Enroll code | Ephemeral UI input | Once, over HTTPS |
| `device_token` | Keychain | `Authorization: Bearer` |
| WG PrivateKey / PSK | Config file mode `0600` | Inside `apply_wg_config` over HTTPS |
| Command signing key (server) | Control Server only | Public key to agent at enroll |

## Remote commands

Every command carries `id`, `type`, `issued_at`, `expires_at`, and a server signature.

- Expired or invalid signatures are ignored.
- Each `id` executes at most once (idempotent acknowledgement).

## Logging

Log sinks must never emit: `PrivateKey`, `PresharedKey`, `device_token`, enroll codes, or full conf bodies. Prefer stable error **codes** over raw backend strings that might echo secrets.

## Remote desktop

Remote mouse/keyboard uses a self-hosted RustDesk relay. Treat **Remote on** as highly privileged (full desktop control). Disable after use; revoke clears the session on the agent. Never paste session passwords into tickets.

## Reporting vulnerabilities

Follow the root [SECURITY.md](../SECURITY.md). Never attach production keys, live tokens, or valid enroll codes to public issues.
