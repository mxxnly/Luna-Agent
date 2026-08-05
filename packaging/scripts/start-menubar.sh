#!/bin/bash
# Wait for Aqua, then start LunaAgent menu bar (LSUIElement).
# Used by ~/Library/LaunchAgents/com.lunaagent.ui.plist on macOS 13+ beta.
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

APP="/Applications/LunaAgent.app"
BIN="${APP}/Contents/MacOS/LunaAgent"

if [[ ! -x "$BIN" ]]; then
  exit 0
fi

# Dock means the menu bar session can host a status item.
for _ in $(seq 1 60); do
  if pgrep -x Dock >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
sleep 3

# Already running (manual open / Login Item) — exit 0 so KeepAlive does not loop.
if pgrep -x LunaAgent >/dev/null 2>&1; then
  exit 0
fi

exec "$BIN"
