# Remote desktop

LunaAgent can open a **TeamViewer-like** remote session **without WireGuard**. The Mac connects outbound to your self-hosted RustDesk relay (`hbbs` / `hbbr`); the operator connects with a RustDesk **viewer** on their own PC.

## What the end user installs

**Only LunaAgent** (the `.pkg`). The remote helper is **embedded** in `LunaAgent.app/Contents/Resources/RustDesk-*.app` — there is no separate “install RustDesk from the internet” step on managed Macs.

On first remote session, macOS may ask for **Screen Recording** / **Accessibility** for the helper (system privacy prompts). That is expected.

## Prerequisites (ops)

1. Relay on the panel VPS — see `vpn-control-panel/rustdesk/README.md`.
2. Backend env: `RUSTDESK_ID_SERVER`, `RUSTDESK_KEY` (optional `RUSTDESK_RELAY_SERVER`).
3. Rebuild agent with `make installer` (runs `scripts/fetch-rustdesk.sh` and embeds both arm64 and x86_64 helpers).

## Operator flow

1. Enroll the Mac with LunaAgent only.
2. Device page → **Remote on**.
3. Copy the one-shot **session password**.
4. Wait for heartbeat to show **RustDesk ID**.
5. On your operator PC: install RustDesk (viewer), point Network at your ID server + key, connect with that ID and password.
6. **Remote off** (or revoke) when finished.

The **operator** machine still needs a RustDesk client to view the screen. Managed devices only get LunaAgent.

## Agent commands

| Type | Effect |
|------|--------|
| `remote_session_enable` | Configure embedded helper, set password, start |
| `remote_session_disable` | Clear password / stop helper |

Heartbeat: `remote_session: { enabled, rustdesk_id, relay_ok, error }`.

## Security

- Outbound to your relay only (no inbound ports on the Mac).
- Prefer your own `hbbs`/`hbbr`.
- Session password is temporary; revoke/unenroll disables remote.
