#!/usr/bin/env bash
# Download official RustDesk.app (macOS) into dist for embedding in LunaAgent.
# No separate user install — ships inside LunaAgent.app/Contents/Resources/.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/dist/rustdesk}"
VERSION="${RUSTDESK_VERSION:-1.4.9}"
BASE="https://github.com/rustdesk/rustdesk/releases/download/${VERSION}"

mkdir -p "$OUT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fetch_arch() {
  local arch="$1" # aarch64 | x86_64
  local dest="$OUT/$arch"
  if [[ -x "$dest/RustDesk.app/Contents/MacOS/RustDesk" ]] || [[ -x "$dest/RustDesk.app/Contents/MacOS/rustdesk" ]]; then
    echo "rustdesk $arch already present: $dest/RustDesk.app"
    return 0
  fi
  local dmg="rustdesk-${VERSION}-${arch}.dmg"
  echo "fetching $dmg …"
  curl -fsSL -o "$TMP/$dmg" "$BASE/$dmg"
  local mount
  mount="$(hdiutil attach -nobrowse -readonly "$TMP/$dmg" | awk '/\/Volumes\//{print $3; exit}')"
  if [[ -z "$mount" ]]; then
    echo "error: could not mount $dmg" >&2
    return 1
  fi
  # shellcheck disable=SC2064
  trap 'hdiutil detach "$mount" -quiet || true; rm -rf "$TMP"' EXIT
  rm -rf "$dest"
  mkdir -p "$dest"
  if [[ ! -d "$mount/RustDesk.app" ]]; then
    echo "error: RustDesk.app not in $dmg" >&2
    hdiutil detach "$mount" -quiet || true
    return 1
  fi
  ditto --norsrc --noextattr "$mount/RustDesk.app" "$dest/RustDesk.app"
  hdiutil detach "$mount" -quiet || true
  trap 'rm -rf "$TMP"' EXIT
  echo "ok $dest/RustDesk.app"
}

fetch_arch aarch64
fetch_arch x86_64
ls -la "$OUT"/aarch64 "$OUT"/x86_64 2>/dev/null || true
