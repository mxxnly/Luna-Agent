#!/usr/bin/env bash
# Codesign with Developer ID when available; otherwise no-op with message.
set -euo pipefail
DIST="${1:-dist}"
ID="${APPLE_DEVELOPER_ID_APP:-}"
if [[ -z "$ID" ]]; then
  echo "APPLE_DEVELOPER_ID_APP not set — skipping codesign (dev/CI unsigned ok)"
  exit 0
fi
codesign --force --options runtime --sign "$ID" "$DIST/lunaagentd"
if [[ -f "$DIST/luna-wghelper" ]]; then
  codesign --force --options runtime --sign "$ID" "$DIST/luna-wghelper"
fi
if [[ -d "$DIST/luna-wg" ]]; then
  for bin in "$DIST/luna-wg"/*; do
    [[ -f "$bin" && -x "$bin" ]] || continue
    codesign --force --options runtime --sign "$ID" "$bin" || true
  done
fi
if [[ -d "$DIST/LunaAgent.app" ]]; then
  codesign --force --deep --options runtime --sign "$ID" "$DIST/LunaAgent.app"
fi
if [[ -f "$DIST/LunaAgent.pkg" ]]; then
  productsign --sign "${APPLE_DEVELOPER_ID_INSTALLER:-$ID}" "$DIST/LunaAgent.pkg" "$DIST/LunaAgent-signed.pkg"
  mv "$DIST/LunaAgent-signed.pkg" "$DIST/LunaAgent.pkg"
fi
echo "signed artifacts in $DIST"
