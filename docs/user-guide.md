# User guide

Day-to-day operation of an enrolled LunaAgent Mac.

## Terms

| Term | Meaning |
|------|---------|
| **Control Server URL** | HTTPS base of your panel (example: `https://panel.example.com`). Must work **without** the VPN up. |
| **Enroll code** | Short-lived code from the panel, exchanged once for a `device_token`. |
| **Device ID** | Public identifier shown in the UI — safe to share with support. |
| **WireGuard conf** | Full config applied by the agent. Private material stays on disk (`0600`) and in the helper path. |

## Enroll

1. Open LunaAgent from the menu bar.
2. Enter the **Control URL** and **enroll code** from your administrator.
3. On success the device appears in the panel; the token is stored in the Keychain.

If enroll fails, verify HTTPS URL, system clock, and that the code has not already been consumed.

## Connect and Disconnect

- **Connect** brings the WireGuard interface up through the root helper.
- **Disconnect** tears it down cleanly.
- The control plane can also toggle the tunnel or push a new configuration remotely.

On macOS 13+, Background Items must be approved or the helper will not stay available across reboots.

## WireGuard configuration

Configs arrive from the panel or can be pasted locally where the UI allows it.

- Invalid conf is rejected.
- On apply failure the previous conf is restored when a backup exists.
- Never paste `PrivateKey` / `PresharedKey` into tickets, chat, or screenshots.

## Notifications (macOS 13+)

Optional alerts for unexpected tunnel drops and auto-reconnect. Manual Connect / Disconnect does not generate noise.

## Unenroll / wipe local state

Use the Device tab when available (may require admin unlock). Otherwise remove:

```text
~/Library/Application Support/LunaAgent
```

and the Keychain password item:

```text
service: com.lunaagent.daemon
account: device_token
```

Then re-enroll against the panel.

## Remote desktop

Operators can start a remote session from the panel (**Remote on**) without the VPN. The helper is **bundled inside LunaAgent** — do not install a separate remote app on the managed Mac. See [remote-desktop.md](remote-desktop.md). macOS may still prompt once for Screen Recording / Accessibility.

## Channel-specific install notes

- [macOS 13+](install-13plus.md)
- [Legacy 10.14–12](install-legacy.md)
