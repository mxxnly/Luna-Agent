#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_IN="${1:-$ROOT/dist}"
mkdir -p "$DIST_IN"
DIST="$(cd "$DIST_IN" && pwd)"
APP="$DIST/LunaAgent.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if command -v swift >/dev/null 2>&1; then
  cd "$ROOT/macos/MenuBar"
  swift build -c release
  BIN_DIR="$(swift build -c release --show-bin-path)"
  BIN="$BIN_DIR/LunaAgentMenu"
  if [[ ! -x "$BIN" ]]; then
    echo "missing built menu binary at $BIN" >&2
    ls -la "$BIN_DIR" >&2 || true
    exit 1
  fi
  cp "$BIN" "$APP/Contents/MacOS/LunaAgent"
else
  echo "swift not found; writing stub launcher" >&2
  cat > "$APP/Contents/MacOS/LunaAgent" <<'EOF'
#!/bin/bash
echo "LunaAgent menu bar stub — build macos/MenuBar with Swift toolchain" >&2
exit 1
EOF
  chmod +x "$APP/Contents/MacOS/LunaAgent"
fi

cp "$ROOT/branding/app-icon/AppIcon-512.png" "$APP/Contents/Resources/AppIcon.png" 2>/dev/null || true
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>LunaAgent</string>
  <key>CFBundleIdentifier</key><string>com.lunaagent.app</string>
  <key>CFBundleVersion</key><string>0.1.0</string>
  <key>CFBundleExecutable</key><string>LunaAgent</string>
  <key>LSUIElement</key><true/>
  <key>CFBundlePackageType</key><string>APPL</string>
</dict>
</plist>
EOF
echo "app bundle at $APP"
