#!/usr/bin/env bash
# E2E against mockcontrol + built lunaagentd
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${1:-$ROOT/dist}"
PORT=18081
DATA="$(mktemp -d)"
export LUNA_TEST_MODE=1 LUNA_WG_DRY_RUN=1

"$DIST/mockcontrol" -addr "127.0.0.1:$PORT" -enroll-code test-enroll &
MCPID=$!
trap 'kill $MCPID 2>/dev/null || true; rm -rf "$DATA"' EXIT
sleep 0.5

"$DIST/lunaagentd" \
  -data-dir "$DATA" \
  -socket "$DATA/t.sock" \
  -enroll-url "http://127.0.0.1:$PORT" \
  -enroll-code test-enroll \
  -once

echo "e2e ok"
