#!/usr/bin/env bash
# Publish ~/Desktop/LunaAgent/<VERSION>/ to GitHub Releases.
# MAJOR==0 → --prerelease (beta); MAJOR>=1 → stable.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-${VERSION:-}}"
if [[ -z "$VERSION" ]]; then
  echo "usage: $0 <VERSION>   e.g. 0.0.1" >&2
  exit 1
fi

DIR="${HOME}/Desktop/LunaAgent/${VERSION}"
if [[ ! -d "$DIR" ]]; then
  echo "error: missing $DIR — run: VERSION=${VERSION} make installer" >&2
  exit 1
fi

for f in LunaAgent_13plus.pkg LunaAgent_Legacy_10.14.pkg \
         LunaAgent_13plus.pkg.sha256 LunaAgent_Legacy_10.14.pkg.sha256 \
         INSTALL.txt README-13plus.txt README-Legacy.txt; do
  if [[ ! -f "$DIR/$f" ]]; then
    echo "error: missing $DIR/$f" >&2
    exit 1
  fi
done

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh CLI required" >&2
  exit 1
fi

MAJOR="${VERSION%%.*}"
TAG="v${VERSION}"
TITLE="LunaAgent ${VERSION}"
NOTES_TMP="$(mktemp)"
if [[ "$MAJOR" == "0" ]]; then
  TITLE="LunaAgent ${VERSION} (Beta)"
  sed "s/\$VERSION/${VERSION}/g" "$ROOT/docs/releases/notes-beta.md" >"$NOTES_TMP"
  PRERELEASE=(--prerelease)
else
  sed "s/\$VERSION/${VERSION}/g" "$ROOT/docs/releases/notes-stable.md" >"$NOTES_TMP"
  PRERELEASE=()
fi

cd "$ROOT"
if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  git tag -a "$TAG" -m "$TITLE"
  echo "created tag $TAG"
fi
# gh release create requires the tag on the remote
if ! git ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1; then
  git push origin "$TAG"
fi

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "release $TAG already exists — uploading assets only"
  gh release upload "$TAG" \
    "$DIR/LunaAgent_13plus.pkg" \
    "$DIR/LunaAgent_13plus.pkg.sha256" \
    "$DIR/LunaAgent_Legacy_10.14.pkg" \
    "$DIR/LunaAgent_Legacy_10.14.pkg.sha256" \
    "$DIR/INSTALL.txt" \
    "$DIR/README-13plus.txt" \
    "$DIR/README-Legacy.txt" \
    --clobber
else
  gh release create "$TAG" \
    --title "$TITLE" \
    --notes-file "$NOTES_TMP" \
    "${PRERELEASE[@]}" \
    "$DIR/LunaAgent_13plus.pkg" \
    "$DIR/LunaAgent_13plus.pkg.sha256" \
    "$DIR/LunaAgent_Legacy_10.14.pkg" \
    "$DIR/LunaAgent_Legacy_10.14.pkg.sha256" \
    "$DIR/INSTALL.txt" \
    "$DIR/README-13plus.txt" \
    "$DIR/README-Legacy.txt"
fi
rm -f "$NOTES_TMP"
echo "published https://github.com/mxxnly/Luna-Agent/releases/tag/${TAG}"
