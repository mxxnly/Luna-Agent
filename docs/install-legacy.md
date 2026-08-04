# Install — Legacy macOS 10.14–12 (LunaAgent_Legacy_10.14.pkg)

**Beta** while version is `0.x.y`. For Mojave through Monterey only. On macOS 13+, use [install-13plus.md](install-13plus.md).

## What you get (reduced)

- Basic AppKit UI: enroll, Connect / Disconnect, status, WireGuard conf editor
- No full SwiftUI metrics tabs
- No SMAppService — autostart via `/Library/LaunchAgents` and `/Library/LaunchDaemons`
- Binaries still live **inside** `/Applications/LunaAgent.app`

## Install

Admin password once (postinstall registers launchd jobs):

```bash
cp LunaAgent_Legacy_10.14.pkg /tmp/
sudo installer -pkg /tmp/LunaAgent_Legacy_10.14.pkg -target /
```

Jobs point at:

- `/Applications/LunaAgent.app/Contents/MacOS/lunaagentd`
- `/Applications/LunaAgent.app/Contents/MacOS/LunaAgent` (via `start-menubar.sh`)
- `/Applications/LunaAgent.app/Contents/MacOS/luna-wghelper` (via `start-wghelper.sh`, exits cleanly if app is missing)

## Uninstall

1. Quit LunaAgent; move `/Applications/LunaAgent.app` to Trash.
2. Optional residual cleanup:

```bash
sudo launchctl bootout system/com.lunaagent.wghelper 2>/dev/null || true
launchctl bootout "gui/$(id -u)/com.lunaagent.daemon" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/com.lunaagent.menubar" 2>/dev/null || true
sudo rm -f /Library/LaunchDaemons/com.lunaagent.wghelper.plist
sudo rm -f /Library/LaunchAgents/com.lunaagent.daemon.plist
sudo rm -f /Library/LaunchAgents/com.lunaagent.menubar.plist
```

## Troubleshooting

| Symptom | Check |
|---------|--------|
| No menu bar icon after reboot | Dock up? `launchctl print gui/$(id -u)/com.lunaagent.menubar` |
| Daemon missing | `launchctl print gui/$(id -u)/com.lunaagent.daemon` |
| VPN needs password every time | Helper LaunchDaemon not loaded — reinstall Legacy pkg |
