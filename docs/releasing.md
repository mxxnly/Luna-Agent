# Releasing

## Version scheme

| Line | Versions | GitHub |
|------|----------|--------|
| **Beta** | `0.0.1` … `0.99.99` | **Pre-release** |
| **Stable** | `1.0.0`+ | Latest release |

**Beta (`0.MINOR.PATCH`):** PATCH = bugfix; MINOR = features / larger changes.  
**Stable (`MAJOR.MINOR.PATCH`):** PATCH = bugfix; MINOR = small changes; MAJOR = significant changes.

No `-beta` suffix: major `0` means beta.

Tags: `v0.0.1`, `v1.0.0`.

## Build artifacts

```bash
VERSION=0.0.1 make installer
# → ~/Desktop/LunaAgent/0.0.1/{pkgs, sha256, INSTALL.txt, README-*.txt}
```

## Publish to GitHub Releases

Requires [GitHub CLI](https://cli.github.com/) (`gh auth login`) and push access to `mxxnly/Luna-Agent`.

```bash
VERSION=0.0.1 make publish-release
# or:
./scripts/publish-github-release.sh 0.0.1
```

The script:

1. Reads `~/Desktop/LunaAgent/$VERSION/`.
2. Creates tag `v$VERSION` if missing.
3. `gh release create` with `--prerelease` when major is `0`.
4. Uploads both pkgs, sha256 files, and the three txt docs.
5. Uses notes from `docs/releases/notes-beta.md` or `notes-stable.md`.

## Checklist

- [ ] `make ci` green
- [ ] Manual smoke on a target Mac (enroll + Connect) for the channel you ship
- [ ] `VERSION=… make installer`
- [ ] Spot-check Desktop `INSTALL.txt` / sha256
- [ ] `make publish-release`
- [ ] Confirm Pre-release vs Latest on the GitHub Releases page

## First beta

Ship **`v0.0.1`** as the first dual-installer Pre-release when ready.
