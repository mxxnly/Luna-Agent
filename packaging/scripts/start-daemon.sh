#!/bin/bash
# Resolve HOME reliably under launchd, then exec lunaagentd.
set -euo pipefail
export PATH="/usr/local/libexec/luna-wg:/opt/homebrew/bin:/usr/local/bin:/usr/sbin:/sbin:/usr/bin:/bin"

if [[ -z "${HOME:-}" || "$HOME" == "/" ]]; then
  HOME="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
  HOME="${HOME:-/Users/$(id -un)}"
  export HOME
fi

LOG_DIR="${HOME}/Library/Logs/LunaAgent"
mkdir -p "$LOG_DIR"
exec /usr/local/bin/lunaagentd >>"${LOG_DIR}/daemon.out.log" 2>>"${LOG_DIR}/daemon.err.log"
