#!/usr/bin/env bash
# Staging checklist after installing a notarized pkg on a clean Mac profile.
set -euo pipefail
echo "== LunaAgent release smoke =="
echo "1) Confirm Gatekeeper accepts the app (no unidentified developer block)"
spctl -a -vv /Applications/LunaAgent.app 2>&1 || echo "(app may not be installed yet)"
echo "2) Confirm daemon binary exists"
test -x /usr/local/bin/lunaagentd && echo "lunaagentd ok" || echo "MISSING lunaagentd"
echo "3) Manual: enroll against staging Control Server, Connect/Disconnect, push conf, revoke"
echo "4) grep logs for secrets:"
echo "   grep -E 'PrivateKey|device_token|PresharedKey' ~/Library/Logs/LunaAgent/* || true"
echo "smoke checklist printed"
