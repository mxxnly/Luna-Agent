import AppKit

enum BrandAssets {
  enum MenuBarState {
    case idle
    case vpnOn
    case offline
  }

  /// High-contrast menu bar mark. VPN-on is a colored (non-template) badge so it stays visible on dark bars.
  static func menuBarImage(state: MenuBarState) -> NSImage {
    switch state {
    case .vpnOn:
      return vpnOnBadge(pointSize: 18)
    case .offline:
      let img = idleMoonTemplate()
      img.isTemplate = true
      return img
    case .idle:
      return idleMoonTemplate()
    }
  }

  static func menuBarTemplate(vpnConnected: Bool = false) -> NSImage {
    menuBarImage(state: vpnConnected ? .vpnOn : .idle)
  }

  /// Square sidebar mark — forced 1:1 pixel aspect (avoids DPI-squashed NSImage).
  static func appIconImage() -> NSImage {
    let names = ["SidebarMark", "MarkSquare", "AppIconSquare", "AppIcon"]
    for name in names {
      if let img = loadSquareImage(named: name) {
        return img
      }
    }
    return drawnSidebarMark(size: 128)
  }

  static func markImage() -> NSImage? { appIconImage() }

  private static func loadSquareImage(named name: String) -> NSImage? {
    guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
          let data = try? Data(contentsOf: url),
          let rep = NSBitmapImageRep(data: data) else { return nil }
    let pw = rep.pixelsWide
    let ph = rep.pixelsHigh
    guard pw > 0, ph > 0 else { return nil }

    // Center-crop to square if needed, always expose 1:1 point size.
    let side = min(pw, ph)
    let ox = (pw - side) / 2
    let oy = (ph - side) / 2
    guard let cg = rep.cgImage?.cropping(to: CGRect(x: ox, y: oy, width: side, height: side)) else {
      let img = NSImage(size: NSSize(width: side, height: side))
      img.addRepresentation(rep)
      img.size = NSSize(width: CGFloat(side), height: CGFloat(side))
      return img
    }
    let cropped = NSBitmapImageRep(cgImage: cg)
    let img = NSImage(size: NSSize(width: side, height: side))
    img.addRepresentation(cropped)
    img.size = NSSize(width: CGFloat(side), height: CGFloat(side))
    return img
  }

  private static func loadTemplateFromBundle() -> NSImage? {
    let names = ["MenuBarTemplate@2x", "MenuBarTemplate"]
    for name in names {
      guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
            let src = NSImage(contentsOf: url) else { continue }
      let img = NSImage(size: NSSize(width: 18, height: 18))
      img.lockFocus()
      src.draw(
        in: NSRect(x: 0, y: 0, width: 18, height: 18),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
      )
      img.unlockFocus()
      img.isTemplate = true
      return img
    }
    return nil
  }

  /// Vector-ish crescent on midnight — no baked-in squircle frame.
  static func drawnSidebarMark(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
      NSColor(red: 0.043, green: 0.071, blue: 0.125, alpha: 1).setFill()
      NSBezierPath(rect: rect).fill()

      NSColor(red: 0.910, green: 0.933, blue: 0.969, alpha: 1).setFill()
      let moonSize = size * 0.58
      let moonOrigin = NSPoint(x: (size - moonSize) / 2, y: (size - moonSize) / 2)
      let outer = NSRect(origin: moonOrigin, size: NSSize(width: moonSize, height: moonSize))
      NSBezierPath(ovalIn: outer).fill()

      NSGraphicsContext.current?.compositingOperation = .destinationOut
      let cut = outer.offsetBy(dx: moonSize * 0.28, dy: moonSize * 0.02)
        .insetBy(dx: moonSize * 0.02, dy: moonSize * 0.02)
      NSBezierPath(ovalIn: cut).fill()
      // punch through to midnight by filling cut with destinationOut then restore bg in hole — 
      // destinationOut makes transparent; redraw midnight in transparent region:
      NSGraphicsContext.current?.compositingOperation = .sourceOver
      NSColor(red: 0.043, green: 0.071, blue: 0.125, alpha: 1).setFill()
      NSBezierPath(ovalIn: cut).fill()

      NSColor(red: 0.910, green: 0.933, blue: 0.969, alpha: 1).setFill()
      let dotR = moonSize * 0.12
      let dot = NSRect(
        x: outer.midX + moonSize * 0.22,
        y: outer.midY + moonSize * 0.18,
        width: dotR,
        height: dotR
      )
      NSBezierPath(ovalIn: dot).fill()
      return true
    }
  }

  private static func idleMoonTemplate() -> NSImage {
    if let fromBundle = loadTemplateFromBundle() {
      return fromBundle
    }
    return drawnCrescentTemplate(size: 18)
  }

  /// Vivid green disc + white check — readable on light and dark menu bars.
  static func vpnOnBadge(pointSize: CGFloat) -> NSImage {
    let size = NSSize(width: pointSize, height: pointSize)
    let img = NSImage(size: size, flipped: false) { rect in
      // Soft dark ring so green pops on light wallpaper too.
      NSColor.black.withAlphaComponent(0.22).setFill()
      NSBezierPath(ovalIn: rect).fill()

      let green = NSColor(calibratedRed: 0.15, green: 0.82, blue: 0.40, alpha: 1)
      green.setFill()
      NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()

      // White checkmark.
      NSColor.white.setStroke()
      let check = NSBezierPath()
      check.lineWidth = max(1.6, pointSize * 0.12)
      check.lineCapStyle = .round
      check.lineJoinStyle = .round
      let inset = rect.insetBy(dx: pointSize * 0.28, dy: pointSize * 0.28)
      check.move(to: NSPoint(x: inset.minX, y: inset.midY))
      check.line(to: NSPoint(x: inset.minX + inset.width * 0.32, y: inset.minY + inset.height * 0.08))
      check.line(to: NSPoint(x: inset.maxX, y: inset.maxY - inset.height * 0.05))
      check.stroke()
      return true
    }
    img.isTemplate = false
    return img
  }

  static func drawnCrescentTemplate(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
      NSColor.black.setFill()
      let inset = rect.insetBy(dx: size * 0.12, dy: size * 0.12)
      NSBezierPath(ovalIn: inset).fill()
      NSGraphicsContext.current?.compositingOperation = .destinationOut
      let cut = inset.offsetBy(dx: size * 0.22, dy: size * 0.02)
      NSBezierPath(ovalIn: cut).fill()
      NSGraphicsContext.current?.compositingOperation = .sourceOver
      let dotR = size * 0.11
      let dot = NSRect(
        x: rect.midX + size * 0.18,
        y: rect.midY + size * 0.12,
        width: dotR,
        height: dotR
      )
      NSBezierPath(ovalIn: dot).fill()
      return true
    }
    img.isTemplate = true
    return img
  }
}
