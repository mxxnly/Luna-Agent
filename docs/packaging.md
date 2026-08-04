# Packaging

## Dual installers

`scripts/build_installer.sh` (also `make installer`) builds:

| Output | Audience |
|--------|----------|
| `LunaAgent_13plus.pkg` | macOS 13+ (productbuild + Welcome/ReadMe) |
| `LunaAgent_Legacy_10.14.pkg` | macOS 10.14–12 (+ postinstall launchd) |

Published to:

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

Symlinks `~/Desktop/LunaAgent/LATEST` and `LATEST-beta` → current `<VERSION>`. Older version folders are kept.

Default `VERSION` is `0.0.1` (beta). Override: `VERSION=0.0.2 make installer`.

## App bundle layout (both channels)

```text
LunaAgent.app/Contents/
  MacOS/LunaAgent
  MacOS/lunaagentd
  MacOS/luna-wghelper
  Resources/luna-wg/{bash,wg,wg-quick,wireguard-go}
  Resources/AppIcon.icns
```

**13+ only:** `Contents/Library/LaunchAgents/com.lunaagent.daemon.plist` and `LaunchDaemons/com.lunaagent.wghelper.plist` with `BundleProgram`.

**Legacy pkg also stages:** `/Library/LaunchAgents|Daemons` plists with absolute paths into `/Applications/LunaAgent.app/...`, plus `start-menubar.sh` / `start-wghelper.sh` under Resources.

## Templates

Short Desktop/release text lives in [`packaging/docs/`](../packaging/docs/) and is filled by `build_installer.sh` (BETA banner + links to this GitHub `docs/` tree).

## Deprecated

`scripts/package.sh` — single experimental pkg; prefer `build_installer.sh`.
