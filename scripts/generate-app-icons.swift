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
// Transparent outside the macOS squircle so Finder/Dock never show a hard square
// (unsigned/LSUIElement builds sometimes skip the system icon mask on Sonoma).
let canvas = NSRect(x: 0, y: 0, width: size, height: size)
NSColor.clear.setFill()
canvas.fill()
let radius = CGFloat(size) * 0.2237
let squircle = NSBezierPath(roundedRect: canvas, xRadius: radius, yRadius: radius)
squircle.addClip()
// Full-bleed mark inside the mask (source is already square art).
srcImg.draw(
  in: canvas,
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
