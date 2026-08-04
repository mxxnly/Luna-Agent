# Releasing

LunaAgent uses SemVer with an explicit beta line. There is no `-beta` suffix in the version string — **major `0` is beta by definition**.

## Version lines

| Line | Versions | GitHub Release |
|------|----------|----------------|
| **Beta** | `0.0.1` … `0.99.99` | **Pre-release** |
| **Stable** | `1.0.0` and above | **Latest** (not pre-release) |

**Within beta (`0.MINOR.PATCH`)**

- `PATCH` — bug fixes only  
- `MINOR` — features or larger functional changes  
- `MAJOR` stays `0` until you cut stable  

**Within stable (`MAJOR.MINOR.PATCH`)**

- `PATCH` — bug fixes  
- `MINOR` — small, compatible changes  
- `MAJOR` — significant or breaking changes  

Tags: `v0.0.1`, `v1.0.0`. Release titles: `LunaAgent 0.0.1 (Beta)` vs `LunaAgent 1.0.0`.

## Build artifacts

```bash
VERSION=0.0.1 make installer
# → ~/Desktop/LunaAgent/0.0.1/
```

Confirm packages, checksums, and `INSTALL.txt` before publishing.

## Publish

Requires [GitHub CLI](https://cli.github.com/) (`gh auth login`) and push access to `mxxnly/Luna-Agent`.

```bash
VERSION=0.0.1 make publish-release
# equivalent:
./scripts/publish-github-release.sh 0.0.1
```

The script:

1. Reads `~/Desktop/LunaAgent/$VERSION/`
2. Creates annotated tag `v$VERSION` if missing and pushes it
3. Creates the GitHub Release (`--prerelease` when major is `0`)
4. Uploads both packages, `.sha256` files, and the three text docs
5. Fills notes from `docs/releases/notes-beta.md` or `notes-stable.md`

## Checklist

- [ ] `make ci` is green
- [ ] Smoke enroll + Connect on a real Mac for the channel you ship
- [ ] `VERSION=… make installer`
- [ ] Spot-check Desktop folder (checksums, BETA banner, doc links)
- [ ] `make publish-release`
- [ ] Confirm Pre-release vs Latest on the Releases page

First public beta: **`v0.0.1`**.
