# Install — macOS 13+ (LunaAgent_13plus.pkg)

**Beta** while version is `0.x.y`. Requires macOS 13 Ventura or newer.

## What this package installs

Only:

- `/Applications/LunaAgent.app`

Inside the app:

- `Contents/MacOS/LunaAgent` — menu bar UI (SwiftUI)
- `Contents/MacOS/lunaagentd` — user agent
- `Contents/MacOS/luna-wghelper` — root WireGuard helper (via SMAppService)
- `Contents/Resources/luna-wg/` — bash, wg, wg-quick, wireguard-go
- `Contents/Library/LaunchAgents|Daemons/*.plist` — embedded for SMAppService (`BundleProgram`)

No primary install under `/usr/local`.

## First launch

1. Open LunaAgent.
2. Complete **Finish setup (Beta)**:
   - Register login item, background agent, WireGuard helper (`SMAppService`)
   - Optionally allow notifications
3. If status is “Needs approval”, open **System Settings → General → Login Items & Extensions** and allow LunaAgent.
4. Enroll and Connect — [user-guide.md](user-guide.md).

## Uninstall

Move **LunaAgent.app** to Trash. SMAppService-registered services unregister with the app.

Enrollment data may remain in:

- `~/Library/Application Support/LunaAgent`
- Keychain item for the device token

Clear enrollment from the UI when available, or remove that folder / keychain item manually.

## Troubleshooting

| Symptom | Check |
|---------|--------|
| Agent offline | Login Items approval; `pgrep -lf lunaagentd` |
| Helper / VPN fails | Helper daemon approved; look at Console for `luna-wghelper` |
| Old `/usr/local` binaries | Leftover from pre-0.0.1 scatter installs — safe to remove after migrating to 13plus pkg |
| Icon / app not updating | Reinstall; upgrades set `BundleIsVersionChecked=false` |

More: [architecture.md](architecture.md), [packaging.md](packaging.md).
