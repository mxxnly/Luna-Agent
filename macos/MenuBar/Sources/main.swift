import AppKit
import Foundation

@main
struct LunaAgentMenuMain {
  static func main() {
    let app = NSApplication.shared
    if #available(macOS 13.0, *) {
      let delegate = AppDelegate()
      app.delegate = delegate
    } else {
      let delegate = BasicAppDelegate()
      app.delegate = delegate
    }
    app.setActivationPolicy(.accessory)
    app.run()
  }
}
