# Install LunaAgent

## Pick the package

| Your macOS | Package |
|------------|---------|
| 13.0 Ventura or newer | `LunaAgent_13plus.pkg` |
| 10.14 Mojave – 12 Monterey | `LunaAgent_Legacy_10.14.pkg` |

Check version: `sw_vers -productVersion`.

On Ventura+, always prefer the **13plus** package. The Legacy package is for older Macs only.

## Download

1. Open [GitHub Releases](https://github.com/mxxnly/Luna-Agent/releases).
2. **Beta** builds (`0.x.y`) are marked **Pre-release**.
3. **Stable** builds start at `1.0.0` and appear as the latest non-prerelease.
4. Download both the `.pkg` you need and its `.sha256` file (or the release notes checksum).

Local beta builds from the maintainer machine also land in `~/Desktop/LunaAgent/<VERSION>/` with `INSTALL.txt` and channel READMEs.

## Verify checksum

```bash
cd ~/Downloads   # or the release folder
shasum -a 256 -c LunaAgent_13plus.pkg.sha256
# or Legacy:
shasum -a 256 -c LunaAgent_Legacy_10.14.pkg.sha256
```

## Install

Desktop / Downloads can be blocked for `installer` by TCC. Copy to `/tmp` first:

```bash
cp LunaAgent_13plus.pkg /tmp/
sudo installer -pkg /tmp/LunaAgent_13plus.pkg -target /
```

Or double-click the pkg (admin password). If Gatekeeper blocks: Right-click → Open.

## After install

1. Open **LunaAgent** from Applications (menu bar icon).
2. Follow the first-launch setup (13+: allow Background / Login Items if prompted).
3. Enroll with Control URL + enroll code from your panel — see [user-guide.md](user-guide.md).

Channel-specific notes:

- [install-13plus.md](install-13plus.md)
- [install-legacy.md](install-legacy.md)
