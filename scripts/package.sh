#!/usr/bin/env bash
# DEPRECATED for releases: use ./scripts/build_installer.sh (dual beta pkgs → Desktop).
# Kept for emergency single-channel experiments only.
set -euo pipefail
echo "warning: package.sh is deprecated — prefer: make installer / scripts/build_installer.sh" >&2
export COPYFILE_DISABLE=1
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${1:-$ROOT/dist}"
STAGE="$DIST/pkgroot"
rm -rf "$STAGE"
mkdir -p "$STAGE/Applications"

REQUIRE_UNIVERSAL=1 "$ROOT/scripts/fetch-wg-tools.sh" "$DIST/luna-wg"
if [[ ! -d "$DIST/LunaAgent.app" ]]; then
  echo "error: build app first (make build-app)" >&2
  exit 1
fi
ditto --norsrc --noextattr "$DIST/LunaAgent.app" "$STAGE/Applications/LunaAgent.app"
MACOS="$STAGE/Applications/LunaAgent.app/Contents/MacOS"
WG="$STAGE/Applications/LunaAgent.app/Contents/Resources/luna-wg"
mkdir -p "$MACOS" "$WG" \
  "$STAGE/Applications/LunaAgent.app/Contents/Library/LaunchAgents" \
  "$STAGE/Applications/LunaAgent.app/Contents/Library/LaunchDaemons"
cp -f "$DIST/lunaagentd" "$MACOS/lunaagentd"
cp -f "$DIST/luna-wghelper" "$MACOS/luna-wghelper"
cp -f "$DIST/luna-wg/bash" "$DIST/luna-wg/wg" "$DIST/luna-wg/wg-quick" "$DIST/luna-wg/wireguard-go" "$WG/"
cp -f "$ROOT/packaging/embedded/com.lunaagent.daemon.plist" \
  "$STAGE/Applications/LunaAgent.app/Contents/Library/LaunchAgents/"
cp -f "$ROOT/packaging/embedded/com.lunaagent.wghelper.plist" \
  "$STAGE/Applications/LunaAgent.app/Contents/Library/LaunchDaemons/"
chmod 755 "$MACOS/"* "$WG/"* 2>/dev/null || true

COMP_PLIST="$DIST/components.plist"
pkgbuild --analyze --root "$STAGE" "$COMP_PLIST" 2>/dev/null || true
if [[ -f "$COMP_PLIST" ]]; then
  /usr/bin/plutil -replace BundleIsRelocatable -bool false "$COMP_PLIST" 2>/dev/null || true
  /usr/bin/plutil -replace BundleIsVersionChecked -bool false "$COMP_PLIST" 2>/dev/null || true
fi
PKG_ARGS=(--root "$STAGE" --identifier com.lunaagent.pkg --version "${VERSION:-0.0.1}" --install-location /)
if [[ -f "$COMP_PLIST" ]]; then
  PKG_ARGS+=(--component-plist "$COMP_PLIST")
fi
pkgbuild "${PKG_ARGS[@]}" "$DIST/LunaAgent.pkg"
shasum -a 256 "$DIST/LunaAgent.pkg" | tee "$DIST/LunaAgent.pkg.sha256"
echo "package $DIST/LunaAgent.pkg (deprecated — use build_installer.sh)"
