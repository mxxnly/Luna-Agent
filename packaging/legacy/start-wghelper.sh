#!/bin/bash
# Legacy LaunchDaemon wrapper: stop spinning after the app is trashed.
set -euo pipefail
APP="/Applications/LunaAgent.app"
BIN="${APP}/Contents/MacOS/luna-wghelper"
if [[ ! -x "$BIN" ]]; then
  exit 0
fi
exec "$BIN"
