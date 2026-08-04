# Legacy channel (macOS 10.14–12)

Package: **`LunaAgent_Legacy_10.14.pkg`** · Range: **Mojave through Monterey** · Line: beta while version is `0.x.y`.

On Ventura or newer, use the [13+ package](install-13plus.md) instead.

## Product differences

Legacy targets older system APIs. Expect:

- **AppKit** status UI — enroll, Connect / Disconnect, status, WireGuard conf
- **No** full SwiftUI metrics experience
- **No** SMAppService — autostart via `/Library/LaunchAgents` and `/Library/LaunchDaemons`
- Binaries still live **inside** `/Applications/LunaAgent.app` (same self-contained layout as 13+)

## Install

Postinstall needs an admin password once to register launchd jobs:

```bash
cp LunaAgent_Legacy_10.14.pkg /tmp/
sudo installer -pkg /tmp/LunaAgent_Legacy_10.14.pkg -target /
```

Registered jobs target paths inside the app (via thin wrapper scripts where needed):

- `…/Contents/MacOS/lunaagentd`
- `…/Contents/MacOS/LunaAgent` (menu bar, delayed until the session is ready)
- `…/Contents/MacOS/luna-wghelper` (exits cleanly if the app is gone — no crash loop)

## Uninstall

1. Quit LunaAgent and move `/Applications/LunaAgent.app` to Trash.
2. Remove residual plists if you want a clean machine:

```bash
sudo launchctl bootout system/com.lunaagent.wghelper 2>/dev/null || true
launchctl bootout "gui/$(id -u)/com.lunaagent.daemon" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/com.lunaagent.menubar" 2>/dev/null || true
sudo rm -f /Library/LaunchDaemons/com.lunaagent.wghelper.plist
sudo rm -f /Library/LaunchAgents/com.lunaagent.daemon.plist
sudo rm -f /Library/LaunchAgents/com.lunaagent.menubar.plist
```

## Troubleshooting

| Symptom | What to check |
|---------|----------------|
| No menu bar icon after reboot | Session ready? `launchctl print "gui/$(id -u)/com.lunaagent.menubar"` |
| Daemon not running | `launchctl print "gui/$(id -u)/com.lunaagent.daemon"` |
| Password prompt on every VPN action | Helper LaunchDaemon not loaded — reinstall this package |
