#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${1:-$ROOT/dist}"
STAGE="$DIST/pkgroot"
rm -rf "$STAGE"
mkdir -p "$STAGE/usr/local/bin" "$STAGE/Applications" \
  "$STAGE/Library/LaunchAgents"

cp "$DIST/lunaagentd" "$STAGE/usr/local/bin/lunaagentd"
cp -R "$DIST/LunaAgent.app" "$STAGE/Applications/" 2>/dev/null || true

cp "$ROOT/packaging/launchd/com.lunaagent.daemon.plist.example" \
  "$STAGE/Library/LaunchAgents/com.lunaagent.daemon.plist"

# Rewrite ProgramArguments path
sed -i.bak 's|/usr/local/bin/lunaagentd|/usr/local/bin/lunaagentd|' \
  "$STAGE/Library/LaunchAgents/com.lunaagent.daemon.plist" || true
rm -f "$STAGE/Library/LaunchAgents/com.lunaagent.daemon.plist.bak"

pkgbuild --root "$STAGE" \
  --identifier com.lunaagent.pkg \
  --version "${VERSION:-0.1.0}" \
  "$DIST/LunaAgent.pkg"

shasum -a 256 "$DIST/LunaAgent.pkg" | tee "$DIST/LunaAgent.pkg.sha256"
echo "package $DIST/LunaAgent.pkg"
