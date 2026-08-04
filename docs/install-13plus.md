# macOS 13+ channel

Package: **`LunaAgent_13plus.pkg`** · Minimum OS: **Ventura 13.0** · Line: beta while version is `0.x.y`.

This is the primary distribution for modern Macs.

## What lands on disk

A single application:

```text
/Applications/LunaAgent.app
```

Everything the product needs is inside the bundle:

| Path | Role |
|------|------|
| `Contents/MacOS/LunaAgent` | Menu bar UI (SwiftUI) |
| `Contents/MacOS/lunaagentd` | User agent (enroll, heartbeat, commands) |
| `Contents/MacOS/luna-wghelper` | Root WireGuard helper |
| `Contents/Resources/luna-wg/` | `bash`, `wg`, `wg-quick`, `wireguard-go` |
| `Contents/Library/LaunchAgents|Daemons/*.plist` | SMAppService `BundleProgram` definitions |

No scatter under `/usr/local`.

## First launch

1. Open LunaAgent.
2. Complete **Finish setup**:
   - Register login item, background agent, and WireGuard helper via `SMAppService`
   - Optionally enable notifications
3. If status shows that approval is required, open  
   **System Settings → General → Login Items & Extensions** and allow LunaAgent.
4. Enroll and connect — [user guide](user-guide.md).

Without Background Items approval, the helper cannot stay privileged and VPN operations will fail intermittently.

## Uninstall

Move **LunaAgent.app** to Trash. SMAppService jobs unregister with the app.

Local enrollment may remain until you clear it:

- `~/Library/Application Support/LunaAgent`
- Keychain item for the device token (`com.lunaagent.daemon` / `device_token`)

Prefer unenroll in the UI when available.

## Troubleshooting

| Symptom | What to check |
|---------|----------------|
| Agent / menu bar missing after reboot | Open LunaAgent once (installs login fallbacks). Also: **System Settings → Login Items & Extensions** → allow LunaAgent. Beta builds also install `~/Library/LaunchAgents/com.lunaagent.ui.plist` + `com.lunaagent.agent.plist`. |
| Agent offline after reboot | `pgrep -lf lunaagentd`; `launchctl print "gui/$(id -u)/com.lunaagent.agent"` |
| Connect fails / helper errors | Helper approved in Login Items; Console logs for `luna-wghelper` |
| Leftover `/usr/local` binaries | Pre–0.0.1 scatter installs — remove after migrating to this package |
| Stale icon or binary after upgrade | Reinstall the pkg (`BundleIsVersionChecked` is disabled for upgrades) |

See also [architecture](architecture.md) and [packaging](packaging.md).
