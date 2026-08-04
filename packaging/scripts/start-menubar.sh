#!/bin/bash
# Wait for GUI session, then start LunaAgent menu bar (LSUIElement).
# Used by /Library/LaunchAgents/com.lunaagent.menubar.plist — `open -ga` at
# login often races WindowServer/Dock and never retries without KeepAlive.
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

APP="/Applications/LunaAgent.app"
BIN="${APP}/Contents/MacOS/LunaAgent"

if [[ ! -x "$BIN" ]]; then
  echo "LunaAgent binary missing: $BIN" >&2
  exit 1
fi

# Dock is a reliable signal that Aqua is up enough to host a status item.
for _ in $(seq 1 30); do
  if pgrep -x Dock >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
sleep 2

# If Login Item / SMAppService already started us, stay attached so KeepAlive
# can relaunch after the user quits the app.
if pid="$(pgrep -nx LunaAgent 2>/dev/null || true)" && [[ -n "$pid" ]]; then
  while kill -0 "$pid" 2>/dev/null; do
    sleep 5
  done
  exit 1
fi

exec "$BIN"
