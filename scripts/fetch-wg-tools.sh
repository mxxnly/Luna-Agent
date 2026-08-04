#!/usr/bin/env bash
# Fetch/build WireGuard userspace tools into dist/luna-wg for packaging.
# Prefers copying from Homebrew when available; otherwise builds wireguard-go
# and downloads the official wg-quick script.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_IN="${1:-$ROOT/dist/luna-wg}"
mkdir -p "$OUT_IN"
OUT="$(cd "$OUT_IN" && pwd)"
WG_GO_REF="${WG_GO_REF:-0.0.20250522}"
WG_TOOLS_REF="${WG_TOOLS_REF:-master}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

copy_brew() {
  local name="$1"
  for p in "/opt/homebrew/bin/$name" "/usr/local/bin/$name"; do
    if [[ -x "$p" ]]; then
      cp -f "$p" "$OUT/$name"
      chmod 755 "$OUT/$name"
      echo "copied $p -> $OUT/$name"
      return 0
    fi
  done
  return 1
}

have_all() {
  [[ -x "$OUT/wireguard-go" && -x "$OUT/wg-quick" && -x "$OUT/bash" && -x "$OUT/wg" ]]
}


is_universal() {
  local f="$1"
  local arches
  arches="$(lipo -archs "$f" 2>/dev/null || true)"
  grep -q 'arm64' <<<"$arches" && grep -q 'x86_64' <<<"$arches"
}

ensure_bash4() {
  local need_build=1
  if [[ -x "$OUT/bash" ]]; then
    if bash_portable_ok "$OUT/bash"; then
      if [[ "${REQUIRE_UNIVERSAL:-}" != "1" ]] || is_universal "$OUT/bash"; then
        need_build=0
      fi
    else
      echo "existing bash not portable for macOS 14 — rebuilding"
      rm -f "$OUT/bash"
    fi
  fi
  if [[ "$need_build" == "0" ]]; then
    fix_wg_quick_shebang
    return 0
  fi

  local deploy="${MACOSX_DEPLOYMENT_TARGET:-10.14}"
  echo "building bash 5.2 universal (macosx-version-min=${deploy})…"
  local src="$TMP/bash-src"
  mkdir -p "$src"
  curl -fsSL https://ftp.gnu.org/gnu/bash/bash-5.2.37.tar.gz | tar xz -C "$src" --strip-components=1
  pushd "$src" >/dev/null

  local sdkroot=""
  for s in \
    /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
    /Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk \
    /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX15.4.sdk \
    /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX15.sdk
  do
    if [[ -d "$s" ]]; then sdkroot="$s"; break; fi
  done
  local sysroot_cflags=""
  if [[ -n "$sdkroot" ]]; then
    sysroot_cflags="-isysroot ${sdkroot}"
    echo "using SDK $sdkroot"
  fi

  build_one() {
    local arch="$1" prefix="$2" min="$3" host="$4"
    make distclean >/dev/null 2>&1 || true
    # Force bash's own strchrnul fallback (SDK on macOS 26 advertises the symbol).
    env ac_cv_func_strchrnul=no ac_cv_have_decl_strchrnul=no \
      CFLAGS="-arch ${arch} -mmacosx-version-min=${min} ${sysroot_cflags}" \
      LDFLAGS="-arch ${arch} -mmacosx-version-min=${min} ${sysroot_cflags}" \
      ./configure --prefix="$prefix" --disable-nls --without-bash-malloc --host="$host" >/dev/null
    make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 2)" >/dev/null
    make install >/dev/null
  }

  build_one arm64 "$TMP/bash-arm64" 11.0 aarch64-apple-darwin
  build_one x86_64 "$TMP/bash-amd64" "$deploy" x86_64-apple-darwin
  popd >/dev/null

  lipo -create -output "$OUT/bash" "$TMP/bash-arm64/bin/bash" "$TMP/bash-amd64/bin/bash"
  chmod 755 "$OUT/bash"
  if ! bash_portable_ok "$OUT/bash"; then
    echo "error: rebuilt bash still not portable:" >&2
    vtool -show-build "$OUT/bash" >&2 || true
    nm -m "$OUT/bash" | grep strchrnul >&2 || true
    exit 1
  fi
  echo "built $OUT/bash ($(lipo -archs "$OUT/bash")) portable"
  fix_wg_quick_shebang
}

# minos < 15 and no strchrnul import (even weak can abort on some dyld paths).
bash_portable_ok() {
  local f="$1"
  if ! bash_minos_ok "$f"; then
    return 1
  fi
  if nm -u "$f" 2>/dev/null | grep -q 'strchrnul'; then
    return 1
  fi
  return 0
}

# True if binary can run on macOS <= ~14 (minos < 15).
bash_minos_ok() {
  local f="$1"
  local info
  info="$(vtool -show-build "$f" 2>/dev/null || true)"
  if [[ -z "$info" ]]; then
    return 0
  fi
  if echo "$info" | grep -E 'minos[[:space:]]+(1[5-9]|[2-9][0-9])\.' >/dev/null; then
    return 1
  fi
  return 0
}

fix_wg_quick_shebang() {
  [[ -f "$OUT/wg-quick" ]] || return 0
  # Point directly at bundled bash so #!/usr/bin/env bash cannot hit /bin/bash 3.2.
  if head -1 "$OUT/wg-quick" | grep -q '^#!'; then
    local rest
    rest="$(tail -n +2 "$OUT/wg-quick")"
    printf '%s\n%s\n' '#!/Applications/LunaAgent.app/Contents/Resources/luna-wg/bash' "$rest" >"$OUT/wg-quick"
    chmod 755 "$OUT/wg-quick"
  fi
}

if have_all && [[ "${FORCE_FETCH_WG:-}" != "1" ]]; then
  if [[ "${REQUIRE_UNIVERSAL:-}" == "1" ]] && ! is_universal "$OUT/wireguard-go"; then
    echo "existing wireguard-go is not universal — rebuilding"
    rm -f "$OUT/wireguard-go"
  elif [[ "${REQUIRE_UNIVERSAL:-}" == "1" ]] && ! is_universal "$OUT/bash"; then
    echo "existing bash is not universal — rebuilding"
    rm -f "$OUT/bash"
  elif [[ "${REQUIRE_UNIVERSAL:-}" == "1" ]] && ! is_universal "$OUT/wg"; then
    echo "existing wg is not universal — rebuilding"
    rm -f "$OUT/wg"
  elif ! bash_portable_ok "$OUT/bash"; then
    echo "existing bash not portable for older Macs — rebuilding"
    rm -f "$OUT/bash"
  else
    fix_wg_quick_shebang
    echo "luna-wg tools already present in $OUT"
    ls -la "$OUT"
    exit 0
  fi
fi

# Prefer brew for scripts / optional wg; wireguard-go must be universal for release pkgs.
if [[ "${REQUIRE_UNIVERSAL:-}" != "1" ]]; then
  copy_brew wireguard-go || true
fi
copy_brew wg-quick || true
# Host-arch brew wg is only useful for local/dev; release pkgs need universal.
if [[ "${REQUIRE_UNIVERSAL:-}" != "1" ]]; then
  copy_brew wg || true
fi

if [[ ! -x "$OUT/wg-quick" ]]; then
  echo "downloading wg-quick ($WG_TOOLS_REF)…"
  curl -fsSL "https://raw.githubusercontent.com/WireGuard/wireguard-tools/${WG_TOOLS_REF}/src/wg-quick/darwin.bash" \
    -o "$OUT/wg-quick"
  # Official file may be named differently on some tags — try linux.bash path fallback via generic script name.
  if ! head -1 "$OUT/wg-quick" | grep -q '^#!'; then
    curl -fsSL "https://raw.githubusercontent.com/WireGuard/wireguard-tools/${WG_TOOLS_REF}/src/wg-quick/linux.bash" \
      -o "$OUT/wg-quick"
  fi
  chmod 755 "$OUT/wg-quick"
fi

if [[ ! -x "$OUT/wireguard-go" ]]; then
  echo "building wireguard-go ($WG_GO_REF) universal…"
  git clone --depth 1 --branch "$WG_GO_REF" https://github.com/WireGuard/wireguard-go.git "$TMP/wireguard-go" \
    || git clone --depth 1 --branch "$WG_GO_REF" https://git.zx2c4.com/wireguard-go "$TMP/wireguard-go"
  pushd "$TMP/wireguard-go" >/dev/null
  GOOS=darwin GOARCH=arm64 go build -o "$TMP/wireguard-go-arm64" .
  GOOS=darwin GOARCH=amd64 go build -o "$TMP/wireguard-go-amd64" .
  lipo -create -output "$OUT/wireguard-go" "$TMP/wireguard-go-arm64" "$TMP/wireguard-go-amd64"
  chmod 755 "$OUT/wireguard-go"
  popd >/dev/null
fi

# Optional brew wg only when not requiring universal (host-arch ok for local/dev).
if [[ "${REQUIRE_UNIVERSAL:-}" != "1" ]]; then
  copy_brew wg || true
fi

if [[ ! -x "$OUT/wg" ]] || { [[ "${REQUIRE_UNIVERSAL:-}" == "1" ]] && ! is_universal "$OUT/wg"; }; then
  echo "building wg (wireguard-tools) universal…"
  rm -f "$OUT/wg"
  git clone --depth 1 --branch "${WG_TOOLS_REF:-master}" https://github.com/WireGuard/wireguard-tools.git "$TMP/wireguard-tools" \
    || git clone --depth 1 https://github.com/WireGuard/wireguard-tools.git "$TMP/wireguard-tools"
  pushd "$TMP/wireguard-tools/src" >/dev/null
  deploy="${MACOSX_DEPLOYMENT_TARGET:-10.14}"
  # BSD make (Xcode): command-line CFLAGS replaces Makefile entirely (no += for
  # -DRUNSTATEDIR). Put -arch on CC/LDFLAGS instead so Makefile CFLAGS stay intact.
  make clean >/dev/null 2>&1 || true
  make PLATFORM=darwin WITH_WGQUICK=no WITH_BASHCOMPLETION=no WITH_SYSTEMDUNITS=no \
    CC="cc -arch arm64 -mmacosx-version-min=11.0" \
    LDFLAGS="-arch arm64 -mmacosx-version-min=11.0"
  cp -f wg "$TMP/wg-arm64"
  make clean >/dev/null 2>&1 || true
  make PLATFORM=darwin WITH_WGQUICK=no WITH_BASHCOMPLETION=no WITH_SYSTEMDUNITS=no \
    CC="cc -arch x86_64 -mmacosx-version-min=${deploy}" \
    LDFLAGS="-arch x86_64 -mmacosx-version-min=${deploy}"
  cp -f wg "$TMP/wg-amd64"
  popd >/dev/null
  lipo -create -output "$OUT/wg" "$TMP/wg-arm64" "$TMP/wg-amd64"
  chmod 755 "$OUT/wg"
  echo "built $OUT/wg ($(lipo -archs "$OUT/wg"))"
fi

ensure_bash4

if ! have_all; then
  echo "error: failed to assemble wireguard-go + wg-quick + bash + wg in $OUT" >&2
  ls -la "$OUT" >&2 || true
  exit 1
fi

echo "luna-wg ready:"
ls -la "$OUT"
file "$OUT/bash" "$OUT/wireguard-go" "$OUT/wg" 2>/dev/null || true
head -1 "$OUT/wg-quick" || true
