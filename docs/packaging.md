# Packaging

LunaAgent ships **two** productbuild packages from one tree. Both embed the same self-contained app; they differ in minimum OS, UI channel, and how background services are registered.

## Build

```bash
VERSION=0.0.1 make installer
# runs scripts/build_installer.sh
```

| Artifact | Audience |
|----------|----------|
| `LunaAgent_13plus.pkg` | macOS 13+ · SMAppService · full UI |
| `LunaAgent_Legacy_10.14.pkg` | macOS 10.14–12 · launchd postinstall · reduced UI |

Output directory:

```text
~/Desktop/LunaAgent/<VERSION>/
  LunaAgent_13plus.pkg
  LunaAgent_13plus.pkg.sha256
  LunaAgent_Legacy_10.14.pkg
  LunaAgent_Legacy_10.14.pkg.sha256
  INSTALL.txt
  README-13plus.txt
  README-Legacy.txt
```

Symlinks `LATEST` and `LATEST-beta` under `~/Desktop/LunaAgent/` always point at the version you just built. Older version folders are left in place as an archive.

Default `VERSION` is `0.0.1` (beta). Override per build: `VERSION=0.1.0 make installer`.

## Bundle layout (both channels)

```text
LunaAgent.app/Contents/
  MacOS/LunaAgent
  MacOS/lunaagentd
  MacOS/luna-wghelper
  Resources/luna-wg/{bash,wg,wg-quick,wireguard-go}
  Resources/RustDesk-aarch64.app
  Resources/RustDesk-x86_64.app
  Resources/AppIcon.icns
```

**13+** also embeds SMAppService plists:

```text
Contents/Library/LaunchAgents/com.lunaagent.daemon.plist
Contents/Library/LaunchDaemons/com.lunaagent.wghelper.plist
```

**Legacy** additionally stages system LaunchAgents/Daemons with absolute paths into `/Applications/LunaAgent.app/...`, plus `start-menubar.sh` / `start-wghelper.sh`.

The remote helper is fetched by `scripts/fetch-rustdesk.sh` and embedded automatically — managed Macs only install LunaAgent.

## Desktop / release copy

Short text files are generated from [`packaging/docs/*.txt.in`](../packaging/docs/) (`__VERSION__` substituted). They stay brief and link to the full guides under `docs/` on GitHub so the two surfaces do not drift.

## Deprecated path

`scripts/package.sh` builds a single experimental package. Prefer `build_installer.sh` for anything you ship.
