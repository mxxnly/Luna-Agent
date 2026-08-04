# Installation

LunaAgent ships as two macOS installer packages. Choose by OS — not by preference.

| macOS | Package | Notes |
|-------|---------|--------|
| **13.0 Ventura or newer** | `LunaAgent_13plus.pkg` | Full UI, SMAppService. Prefer this on every modern Mac. |
| **10.14 Mojave – 12 Monterey** | `LunaAgent_Legacy_10.14.pkg` | Reduced UI. Do not use on Ventura+. |

```bash
sw_vers -productVersion
```

## Get the build

1. Open [GitHub Releases](https://github.com/mxxnly/Luna-Agent/releases).
2. Beta (`0.x.y`) appears as **Pre-release**. Stable (`1.0.0+`) is **Latest**.
3. Download the `.pkg` for your channel **and** the matching `.sha256` file.

Maintainer builds also land in `~/Desktop/LunaAgent/<VERSION>/` with short `INSTALL.txt` / channel READMEs that point back here.

## Verify integrity

```bash
shasum -a 256 -c LunaAgent_13plus.pkg.sha256
# or
shasum -a 256 -c LunaAgent_Legacy_10.14.pkg.sha256
```

Do not install a package that fails checksum verification.

## Run the installer

macOS TCC often blocks `installer` from Desktop or Downloads. Copy to `/tmp` first:

```bash
cp LunaAgent_13plus.pkg /tmp/
sudo installer -pkg /tmp/LunaAgent_13plus.pkg -target /
```

Double-click install works if Gatekeeper allows it. If the UI blocks the package: right-click → **Open**, then confirm.

## After install

1. Launch **LunaAgent** from Applications — a menu-bar icon should appear.
2. On macOS 13+, complete first-launch setup and approve **Login Items / Background Items** when prompted.
3. Enroll with your panel’s Control URL and enroll code — see the [user guide](user-guide.md).

Channel deep-dives:

- [macOS 13+ (SMAppService)](install-13plus.md)
- [Legacy 10.14–12 (launchd)](install-legacy.md)
