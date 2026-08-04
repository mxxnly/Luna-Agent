# User guide

## Concepts

- **Control Server URL** — HTTPS base of your panel (e.g. `https://panel.example.com`). Traffic does not require the VPN to be up.
- **Enroll code** — one-time (or short-lived) code from the panel; exchanged for a `device_token`.
- **Device ID** — public identifier shown in the UI; safe to copy for support.
- **WireGuard conf** — applied by the agent; private keys stay on disk mode `0600` and in the tunnel helper path.

## Enroll

1. Open LunaAgent (menu bar).
2. Enter **Control URL** and **enroll code**.
3. On success the device appears in the panel; token is stored in the Keychain.

If enroll fails: check URL (HTTPS), clock skew, and that the code is unused.

## Connect / Disconnect

- **Connect** brings the tunnel up (via root helper when registered).
- **Disconnect** tears it down.
- Remote commands from the panel can also toggle VPN or push a new conf.

On macOS 13+, approve Background Items so the helper can run without a password each time.

## WireGuard configuration

- Paste or receive a full `.conf` from the panel.
- Invalid conf is rejected; previous conf is restored on apply failure when possible.
- Do not share PrivateKey / PresharedKey in tickets or screenshots.

## Notifications (macOS 13+)

Optional alerts for unexpected tunnel drops / auto-reconnect. Connect/Disconnect you press yourself do not spam banners.

## Unenroll / wipe local state

Use the Device UI to unenroll when available (may require admin unlock). Or remove:

- `~/Library/Application Support/LunaAgent`
- Keychain password item service `com.lunaagent.daemon` account `device_token`

Then reinstall or re-enroll as needed.

## Channels

- Full UI: [install-13plus.md](install-13plus.md)
- Reduced UI: [install-legacy.md](install-legacy.md)
