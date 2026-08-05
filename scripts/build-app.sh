#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_IN="${1:-$ROOT/dist}"
mkdir -p "$DIST_IN"
DIST="$(cd "$DIST_IN" && pwd)"
APP="$DIST/LunaAgent.app"
RES="$APP/Contents/Resources"
mkdir -p "$APP/Contents/MacOS" "$RES"

# Deploy back to Mojave; SwiftUI paths are @available(macOS 13+).
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.14}"

if command -v swift >/dev/null 2>&1; then
  cd "$ROOT/macos/MenuBar"
  # Universal menu bar binary (Apple Silicon + Intel).
  swift build -c release --arch arm64 \
    -Xswiftc -target -Xswiftc "arm64-apple-macosx${MACOSX_DEPLOYMENT_TARGET}"
  swift build -c release --arch x86_64 \
    -Xswiftc -target -Xswiftc "x86_64-apple-macosx${MACOSX_DEPLOYMENT_TARGET}"
  ARM_BIN="$(swift build -c release --arch arm64 --show-bin-path)/LunaAgentMenu"
  X86_BIN="$(swift build -c release --arch x86_64 --show-bin-path)/LunaAgentMenu"
  if [[ ! -x "$ARM_BIN" || ! -x "$X86_BIN" ]]; then
    echo "missing arch builds: arm=$ARM_BIN x86=$X86_BIN" >&2
    exit 1
  fi
  lipo -create -output "$APP/Contents/MacOS/LunaAgent" "$ARM_BIN" "$X86_BIN"
  chmod 755 "$APP/Contents/MacOS/LunaAgent"
else
  echo "swift not found; writing stub launcher" >&2
  cat > "$APP/Contents/MacOS/LunaAgent" <<'EOF'
#!/bin/bash
echo "LunaAgent menu bar stub — build macos/MenuBar with Swift toolchain" >&2
exit 1
EOF
  chmod +x "$APP/Contents/MacOS/LunaAgent"
fi

# --- App icon (.icns) ---
# Ensure square masters (tall plate on white canvas looks squashed in Finder).
"$ROOT/scripts/generate-app-icons.sh"
ICONSET="$DIST/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
ICONS="$ROOT/branding/app-icon"
cp "$ICONS/AppIcon-16.png"      "$ICONSET/icon_16x16.png"
cp "$ICONS/AppIcon-16@2x.png"   "$ICONSET/icon_16x16@2x.png"
cp "$ICONS/AppIcon-32.png"      "$ICONSET/icon_32x32.png"
cp "$ICONS/AppIcon-32@2x.png"   "$ICONSET/icon_32x32@2x.png"
cp "$ICONS/AppIcon-128.png"     "$ICONSET/icon_128x128.png"
cp "$ICONS/AppIcon-128@2x.png"  "$ICONSET/icon_128x128@2x.png"
cp "$ICONS/AppIcon-256.png"     "$ICONSET/icon_256x256.png"
cp "$ICONS/AppIcon-256@2x.png"  "$ICONSET/icon_256x256@2x.png"
cp "$ICONS/AppIcon-512.png"     "$ICONSET/icon_512x512.png"
cp "$ICONS/AppIcon-512@2x.png"  "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"
rm -rf "$ICONSET"
# Do not ship AppIcon.png next to AppIcon.icns — Finder may pick the flat PNG
# and show a hard square instead of the masked .icns.

# --- Menu bar template + window mark ---
MB="$ROOT/branding/menubar"
cp "$MB/MenuBarTemplate-22.png"    "$RES/MenuBarTemplate.png"
cp "$MB/MenuBarTemplate-22@2x.png" "$RES/MenuBarTemplate@2x.png"
cp "$ROOT/branding/mark/sidebar-mark.png" "$RES/SidebarMark.png"
cp "$ROOT/branding/mark/mark-square-dark.png" "$RES/MarkSquare.png"
cp "$ROOT/branding/app-icon/AppIcon-512.png" "$RES/AppIconSquare.png"

VERSION="${VERSION:-0.1.0}"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>LunaAgent</string>
  <key>CFBundleDisplayName</key><string>LunaAgent</string>
  <key>CFBundleIdentifier</key><string>com.lunaagent.app</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleExecutable</key><string>LunaAgent</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>10.14</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSUserNotificationAlertStyle</key><string>alert</string>
</dict>
</plist>
EOF
echo "app bundle at $APP"
