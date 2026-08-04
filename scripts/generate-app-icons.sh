#!/usr/bin/env bash
# Rebuild branding/app-icon/*.png as true square macOS icons from mark-square-dark.
# Old AppIcons were a tall ~2:3 plate on a white canvas → Finder/Launchpad squash.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/branding/mark/mark-square-dark.png"
OUT="$ROOT/branding/app-icon"
mkdir -p "$OUT"
[[ -f "$SRC" ]] || { echo "missing $SRC" >&2; exit 1; }

# Full-bleed square master (padding is already in the mark artwork margins if any).
# Draw onto midnight so corners match brand if source has transparency.
MASTER="$OUT/.AppIcon-master.png"
swift "$ROOT/scripts/generate-app-icons.swift" "$ROOT" "$SRC" "$MASTER"

copy_size() {
  local name="$1" px="$2"
  sips -z "$px" "$px" "$MASTER" --out "$OUT/$name" >/dev/null
}

copy_size AppIcon-1024.png 1024
copy_size AppIcon-512@2x.png 1024
copy_size AppIcon-512.png 512
copy_size AppIcon-256@2x.png 512
copy_size AppIcon-256.png 256
copy_size AppIcon-128@2x.png 256
copy_size AppIcon-128.png 128
copy_size AppIcon-64.png 64
copy_size AppIcon-32@2x.png 64
copy_size AppIcon-32.png 32
copy_size AppIcon-16@2x.png 32
copy_size AppIcon-16.png 16
rm -f "$MASTER"

# Sanity: content must be ~square (not tall plate)
aspect="$(
swift -e '
import AppKit
let url = URL(fileURLWithPath: "'"$OUT"'/AppIcon-1024.png")
guard let img = NSImage(contentsOf: url), let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { fatalError("no") }
var minX=rep.pixelsWide, minY=rep.pixelsHigh, maxX=0, maxY=0
for y in stride(from:0, to:rep.pixelsHigh, by:4) {
  for x in stride(from:0, to:rep.pixelsWide, by:4) {
    guard let c = rep.colorAt(x:x, y:y) else { continue }
    if c.redComponent > 0.95 && c.greenComponent > 0.95 && c.blueComponent > 0.95 { continue }
    minX=min(minX,x); minY=min(minY,y); maxX=max(maxX,x); maxY=max(maxY,y)
  }
}
let a = Double(maxX-minX+1)/Double(maxY-minY+1)
print(String(format: "%.3f", a))
if a < 0.95 || a > 1.05 { exit(2) }
'
)"
echo "content aspect=$aspect"
echo "OK → $OUT"
