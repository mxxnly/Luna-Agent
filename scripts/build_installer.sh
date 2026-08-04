#!/usr/bin/env bash
# Build both beta installers and publish to ~/Desktop/LunaAgent/<VERSION>/.
set -euo pipefail
export COPYFILE_DISABLE=1
export PATH="/usr/sbin:/sbin:/usr/bin:/bin:/opt/homebrew/bin:${PATH:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
VERSION="${VERSION:-0.0.1}"
export VERSION
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.14}"

DESKTOP_REL="${HOME}/Desktop/LunaAgent/${VERSION}"
STAGE_MODERN="$DIST/stage-13plus"
STAGE_LEGACY="$DIST/stage-legacy"
DOCS_IN="$ROOT/packaging/docs"

echo "==> LunaAgent installer VERSION=${VERSION} (0.x = beta)"

cd "$ROOT"
make build
REQUIRE_UNIVERSAL=1 "$ROOT/scripts/fetch-wg-tools.sh" "$DIST/luna-wg"
# UI binary once (deployment 10.14; SwiftUI gated at runtime)
MACOSX_DEPLOYMENT_TARGET=10.14 "$ROOT/scripts/build-app.sh" "$DIST"

assemble_app() {
  local dest_app="$1"
  local min_os="$2"
  local channel="$3" # modern|legacy
  rm -rf "$dest_app"
  ditto --norsrc --noextattr "$DIST/LunaAgent.app" "$dest_app"
  local macos="$dest_app/Contents/MacOS"
  local res="$dest_app/Contents/Resources"
  local wg="$res/luna-wg"
  mkdir -p "$macos" "$wg"

  cp -f "$DIST/lunaagentd" "$macos/lunaagentd"
  cp -f "$DIST/luna-wghelper" "$macos/luna-wghelper"
  chmod 755 "$macos/lunaagentd" "$macos/luna-wghelper" "$macos/LunaAgent"

  cp -f "$DIST/luna-wg/bash" "$DIST/luna-wg/wg" "$DIST/luna-wg/wg-quick" "$DIST/luna-wg/wireguard-go" "$wg/"
  chmod 755 "$wg"/*

  # Display name beta
  /usr/bin/plutil -replace CFBundleDisplayName -string "LunaAgent (Beta)" "$dest_app/Contents/Info.plist"
  /usr/bin/plutil -replace CFBundleName -string "LunaAgent" "$dest_app/Contents/Info.plist"
  /usr/bin/plutil -replace CFBundleShortVersionString -string "$VERSION" "$dest_app/Contents/Info.plist"
  /usr/bin/plutil -replace CFBundleVersion -string "$VERSION" "$dest_app/Contents/Info.plist"
  /usr/bin/plutil -replace LSMinimumSystemVersion -string "$min_os" "$dest_app/Contents/Info.plist"

  if [[ "$channel" == "modern" ]]; then
    mkdir -p "$dest_app/Contents/Library/LaunchAgents" "$dest_app/Contents/Library/LaunchDaemons"
    cp -f "$ROOT/packaging/embedded/com.lunaagent.daemon.plist" \
      "$dest_app/Contents/Library/LaunchAgents/com.lunaagent.daemon.plist"
    cp -f "$ROOT/packaging/embedded/com.lunaagent.wghelper.plist" \
      "$dest_app/Contents/Library/LaunchDaemons/com.lunaagent.wghelper.plist"
  else
    cp -f "$ROOT/packaging/legacy/start-menubar.sh" "$wg/start-menubar.sh"
    cp -f "$ROOT/packaging/legacy/start-wghelper.sh" "$wg/start-wghelper.sh"
    chmod 755 "$wg/start-menubar.sh" "$wg/start-wghelper.sh"
  fi
}

build_component_pkg() {
  local root_dir="$1"
  local ident="$2"
  local out_pkg="$3"
  local scripts_dir="${4:-}"
  local comp="$DIST/components-$(basename "$out_pkg" .pkg).plist"
  pkgbuild --analyze --root "$root_dir" "$comp" 2>/dev/null || true
  if [[ -f "$comp" ]]; then
    /usr/bin/plutil -replace BundleIsRelocatable -bool false "$comp" 2>/dev/null || true
    /usr/bin/plutil -replace BundleIsVersionChecked -bool false "$comp" 2>/dev/null || true
  fi
  local args=(
    --root "$root_dir"
    --identifier "$ident"
    --version "$VERSION"
    --install-location /
  )
  if [[ -f "$comp" ]]; then
    args+=(--component-plist "$comp")
  fi
  if [[ -n "$scripts_dir" && -d "$scripts_dir" ]]; then
    args+=(--scripts "$scripts_dir")
  fi
  pkgbuild "${args[@]}" "$out_pkg"
}

# --- Modern 13+ ---
echo "==> Assembling 13+ app"
rm -rf "$STAGE_MODERN"
mkdir -p "$STAGE_MODERN/Applications"
assemble_app "$STAGE_MODERN/Applications/LunaAgent.app" "13.0" modern
COMPONENT_MODERN="$DIST/LunaAgent_13plus-component.pkg"
build_component_pkg "$STAGE_MODERN" "com.lunaagent.pkg.13plus" "$COMPONENT_MODERN"

DIST_XML_MODERN="$DIST/distribution-13plus.xml"
cat > "$DIST_XML_MODERN" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>LunaAgent (Beta) — macOS 13+</title>
  <organization>com.lunaagent</organization>
  <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
  <options customize="never" require-scripts="false" hostArchitectures="x86_64,arm64"/>
  <welcome file="Welcome.html" mime-type="text/html"/>
  <readme file="ReadMe.html" mime-type="text/html"/>
  <os-version min="13.0"/>
  <pkg-ref id="com.lunaagent.pkg.13plus"/>
  <choices-outline>
    <line choice="default"/>
  </choices-outline>
  <choice id="default" title="LunaAgent">
    <pkg-ref id="com.lunaagent.pkg.13plus"/>
  </choice>
  <pkg-ref id="com.lunaagent.pkg.13plus" version="$VERSION" onConclusion="none">LunaAgent_13plus-component.pkg</pkg-ref>
</installer-gui-script>
EOF

RES_MODERN="$DIST/product-resources-13plus"
rm -rf "$RES_MODERN"
mkdir -p "$RES_MODERN/en.lproj"
cat > "$RES_MODERN/en.lproj/Welcome.html" <<'HTML'
<html><body style="font-family: -apple-system; font-size: 13px;">
<h2>LunaAgent (Beta) for macOS 13+</h2>
<p>This beta installs a self-contained <b>LunaAgent.app</b> in Applications.</p>
<p>On first launch you will be asked to allow <b>Login Items / Background</b> services for the VPN agent and WireGuard helper. No files are installed under <code>/usr/local</code>.</p>
<p>Use the <b>Legacy</b> package only on macOS 10.14–12.</p>
</body></html>
HTML
cat > "$RES_MODERN/en.lproj/ReadMe.html" <<'HTML'
<html><body style="font-family: -apple-system; font-size: 13px;">
<h2>Read Me — Beta</h2>
<ul>
<li>Requires macOS 13 Ventura or newer.</li>
<li>After install, open LunaAgent and complete setup (Background Items + optional notifications).</li>
<li>Uninstall: move LunaAgent to Trash (background services unregister with the app). Enrollment data under Application Support is kept unless you clear it in the UI.</li>
</ul>
</body></html>
HTML

PRODUCT_MODERN="$DIST/LunaAgent_13plus.pkg"
productbuild \
  --distribution "$DIST_XML_MODERN" \
  --resources "$RES_MODERN" \
  --package-path "$DIST" \
  "$PRODUCT_MODERN"

# --- Legacy 10.14–12 ---
echo "==> Assembling Legacy app"
rm -rf "$STAGE_LEGACY"
mkdir -p "$STAGE_LEGACY/Applications" \
  "$STAGE_LEGACY/Library/LaunchAgents" \
  "$STAGE_LEGACY/Library/LaunchDaemons"
assemble_app "$STAGE_LEGACY/Applications/LunaAgent.app" "10.14" legacy
cp -f "$ROOT/packaging/legacy/com.lunaagent.daemon.plist" "$STAGE_LEGACY/Library/LaunchAgents/"
cp -f "$ROOT/packaging/legacy/com.lunaagent.menubar.plist" "$STAGE_LEGACY/Library/LaunchAgents/"
cp -f "$ROOT/packaging/legacy/com.lunaagent.wghelper.plist" "$STAGE_LEGACY/Library/LaunchDaemons/"

SCRIPTS_LEGACY="$DIST/scripts-legacy"
rm -rf "$SCRIPTS_LEGACY"
mkdir -p "$SCRIPTS_LEGACY"
cp -f "$ROOT/packaging/legacy/postinstall" "$SCRIPTS_LEGACY/postinstall"
chmod 755 "$SCRIPTS_LEGACY/postinstall"

COMPONENT_LEGACY="$DIST/LunaAgent_Legacy-component.pkg"
build_component_pkg "$STAGE_LEGACY" "com.lunaagent.pkg.legacy" "$COMPONENT_LEGACY" "$SCRIPTS_LEGACY"

DIST_XML_LEGACY="$DIST/distribution-legacy.xml"
cat > "$DIST_XML_LEGACY" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>LunaAgent Legacy (Beta) — macOS 10.14–12</title>
  <organization>com.lunaagent</organization>
  <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
  <options customize="never" require-scripts="true" hostArchitectures="x86_64,arm64"/>
  <welcome file="Welcome.html" mime-type="text/html"/>
  <readme file="ReadMe.html" mime-type="text/html"/>
  <os-version min="10.14"/>
  <pkg-ref id="com.lunaagent.pkg.legacy"/>
  <choices-outline>
    <line choice="default"/>
  </choices-outline>
  <choice id="default" title="LunaAgent Legacy">
    <pkg-ref id="com.lunaagent.pkg.legacy"/>
  </choice>
  <pkg-ref id="com.lunaagent.pkg.legacy" version="$VERSION" onConclusion="none">LunaAgent_Legacy-component.pkg</pkg-ref>
</installer-gui-script>
EOF

RES_LEGACY="$DIST/product-resources-legacy"
rm -rf "$RES_LEGACY"
mkdir -p "$RES_LEGACY/en.lproj"
cat > "$RES_LEGACY/en.lproj/Welcome.html" <<'HTML'
<html><body style="font-family: -apple-system; font-size: 13px;">
<h2>LunaAgent Legacy (Beta) for macOS 10.14–12</h2>
<p>Reduced UI (enroll, VPN connect/disconnect, WireGuard config). No full metrics/SwiftUI.</p>
<p>Install requires an admin password once to register the WireGuard helper. Prefer <b>LunaAgent_13plus.pkg</b> on macOS 13+.</p>
</body></html>
HTML
cat > "$RES_LEGACY/en.lproj/ReadMe.html" <<'HTML'
<html><body style="font-family: -apple-system; font-size: 13px;">
<h2>Read Me — Legacy Beta</h2>
<ul>
<li>For macOS 10.14 Mojave through 12 Monterey only.</li>
<li>Binaries live inside LunaAgent.app; launchd plists point into Applications.</li>
<li>After deleting the app, residual LaunchAgents/Daemons may remain — see README-Legacy.txt.</li>
</ul>
</body></html>
HTML

PRODUCT_LEGACY="$DIST/LunaAgent_Legacy_10.14.pkg"
productbuild \
  --distribution "$DIST_XML_LEGACY" \
  --resources "$RES_LEGACY" \
  --package-path "$DIST" \
  "$PRODUCT_LEGACY"

# --- Publish to Desktop ---
echo "==> Publishing ${DESKTOP_REL}"
mkdir -p "$DESKTOP_REL"
cp -f "$PRODUCT_MODERN" "$DESKTOP_REL/LunaAgent_13plus.pkg"
cp -f "$PRODUCT_LEGACY" "$DESKTOP_REL/LunaAgent_Legacy_10.14.pkg"
(
  cd "$DESKTOP_REL"
  shasum -a 256 LunaAgent_13plus.pkg | tee LunaAgent_13plus.pkg.sha256
  shasum -a 256 LunaAgent_Legacy_10.14.pkg | tee LunaAgent_Legacy_10.14.pkg.sha256
)

sed "s/__VERSION__/${VERSION}/g" "$DOCS_IN/INSTALL.txt.in" >"$DESKTOP_REL/INSTALL.txt"
sed "s/__VERSION__/${VERSION}/g" "$DOCS_IN/README-13plus.txt.in" >"$DESKTOP_REL/README-13plus.txt"
sed "s/__VERSION__/${VERSION}/g" "$DOCS_IN/README-Legacy.txt.in" >"$DESKTOP_REL/README-Legacy.txt"

# Symlink LATEST → this version (relative)
ln -sfn "$VERSION" "${HOME}/Desktop/LunaAgent/LATEST"
ln -sfn "$VERSION" "${HOME}/Desktop/LunaAgent/LATEST-beta"

echo "==> Done"
echo "    $DESKTOP_REL"
ls -lh "$DESKTOP_REL"
