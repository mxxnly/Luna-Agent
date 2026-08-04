#!/usr/bin/env swift
import AppKit
import Foundation

// Args: root srcPath outMasterPath
guard CommandLine.arguments.count >= 4 else {
  fputs("usage: generate-app-icons.swift <root> <src.png> <out.png>\n", stderr)
  exit(1)
}
let srcPath = CommandLine.arguments[2]
let outPath = CommandLine.arguments[3]
let size = 1024

guard let srcImg = NSImage(contentsOf: URL(fileURLWithPath: srcPath)) else {
  fputs("cannot load \(srcPath)\n", stderr)
  exit(1)
}

let midnight = NSColor(srgbRed: 0x0B / 255.0, green: 0x12 / 255.0, blue: 0x20 / 255.0, alpha: 1)
let rep = NSBitmapImageRep(
  bitmapDataPlanes: nil,
  pixelsWide: size,
  pixelsHigh: size,
  bitsPerSample: 8,
  samplesPerPixel: 4,
  hasAlpha: true,
  isPlanar: false,
  colorSpaceName: .deviceRGB,
  bytesPerRow: 0,
  bitsPerPixel: 0
)!
rep.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
midnight.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()
// Full-bleed mark (already square). Slight inset (~8%) so macOS squircle mask doesn't clip.
let inset = CGFloat(size) * 0.08
srcImg.draw(
  in: NSRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2),
  from: .zero,
  operation: .sourceOver,
  fraction: 1.0,
  respectFlipped: false,
  hints: [.interpolation: NSImageInterpolation.high]
)
NSGraphicsContext.restoreGraphicsState()
guard let data = rep.representation(using: .png, properties: [:]) else {
  fputs("png encode failed\n", stderr)
  exit(1)
}
try data.write(to: URL(fileURLWithPath: outPath), options: .atomic)
print("master \(outPath)")
