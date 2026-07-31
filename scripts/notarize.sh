#!/usr/bin/env bash
set -euo pipefail
DIST="${1:-dist}"
if [[ -z "${APPLE_ID:-}" || -z "${APPLE_TEAM_ID:-}" ]]; then
  echo "APPLE_ID / APPLE_TEAM_ID not set — skipping notarization"
  exit 0
fi
xcrun notarytool submit "$DIST/LunaAgent.pkg" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "${APPLE_APP_SPECIFIC_PASSWORD:?}" \
  --wait
xcrun stapler staple "$DIST/LunaAgent.pkg"
echo "notarized $DIST/LunaAgent.pkg"
