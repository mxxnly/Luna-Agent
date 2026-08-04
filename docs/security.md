# Security notes

## Trust model

- The **Control Server** is trusted after enroll (HTTPS + server command-signing public key).
- The **device token** authenticates the agent; stored in the macOS Keychain (file store only in `LUNA_TEST_MODE=1`).
- **Operators** of the Control Server can push WireGuard configs and toggle the tunnel — treat panel admin access as highly privileged.
- The **WireGuard helper** runs as root (SMAppService daemon or legacy LaunchDaemon) and listens on `/var/run/luna-wg.sock` with peer UID checks.

## Secrets

| Secret | Storage | Transmitted |
|--------|---------|-------------|
| Enroll code | Ephemeral UI input | Once over HTTPS |
| `device_token` | Keychain | `Authorization: Bearer` |
| WG PrivateKey / PSK | Config file mode `0600` | Inside `apply_wg_config` over HTTPS |
| Command signing key (server) | Control Server only | Public key to agent at enroll |

## Command execution

- Every command includes `id`, `type`, `issued_at`, `expires_at`, and a server signature.
- Expired or invalid signatures are ignored.
- Each `id` executes at most once (idempotent ack).

## Logging

Deny-list for log sinks: `PrivateKey`, `PresharedKey`, `device_token`, enroll codes, full conf bodies. Prefer error **codes** over raw backend messages that might echo secrets.

## Reporting

See root [SECURITY.md](../SECURITY.md). Never attach production keys, tokens, or live enroll codes to issues.
