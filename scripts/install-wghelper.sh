#!/usr/bin/env bash
# One-time install of root WireGuard helper (asks for Mac password once).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$(cd "${1:-$ROOT/dist}" && pwd)"
HELPER="$DIST/luna-wghelper"
PLIST="$ROOT/packaging/launchd/com.lunaagent.wghelper.plist"

if [[ ! -x "$HELPER" ]]; then
  echo "missing $HELPER — run: make build" >&2
  exit 1
fi

# Stage outside Desktop/Documents so elevated install isn't blocked by TCC.
STAGE=/tmp/luna-wg-install
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$HELPER" "$STAGE/luna-wghelper"
cp "$PLIST" "$STAGE/com.lunaagent.wghelper.plist"
chmod 755 "$STAGE/luna-wghelper"

cat > "$STAGE/install.sh" <<EOF
#!/bin/bash
set -euo pipefail
mkdir -p /usr/local/libexec
cp "$STAGE/luna-wghelper" /usr/local/libexec/luna-wghelper
chmod 755 /usr/local/libexec/luna-wghelper
cp "$STAGE/com.lunaagent.wghelper.plist" /Library/LaunchDaemons/com.lunaagent.wghelper.plist
chmod 644 /Library/LaunchDaemons/com.lunaagent.wghelper.plist
launchctl bootout system/com.lunaagent.wghelper 2>/dev/null || true
launchctl bootstrap system /Library/LaunchDaemons/com.lunaagent.wghelper.plist
EOF
chmod 755 "$STAGE/install.sh"

if [[ "$(id -u)" -eq 0 ]]; then
  "$STAGE/install.sh"
else
  echo "Installing luna-wghelper (one admin password)…"
  osascript -e "do shell script \"$STAGE/install.sh\" with administrator privileges"
fi

sleep 0.5
if [[ -S /var/run/luna-wg.sock ]]; then
  echo "luna-wghelper ready — VPN connect/disconnect will not ask for password"
else
  echo "helper installed but socket missing — check: sudo launchctl print system/com.lunaagent.wghelper" >&2
  exit 1
fi
