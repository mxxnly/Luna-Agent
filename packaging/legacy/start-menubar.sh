#!/bin/bash
# Legacy LaunchAgent: wait for Dock, then start menu bar from the app bundle.
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
APP="/Applications/LunaAgent.app"
BIN="${APP}/Contents/MacOS/LunaAgent"
if [[ ! -x "$BIN" ]]; then
  exit 0
fi
for _ in $(seq 1 30); do
  if pgrep -x Dock >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
sleep 2
if pid="$(pgrep -nx LunaAgent 2>/dev/null || true)" && [[ -n "$pid" ]]; then
  while kill -0 "$pid" 2>/dev/null; do
    sleep 5
  done
  exit 1
fi
exec "$BIN"
