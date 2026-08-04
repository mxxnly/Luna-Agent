import AppKit
import ServiceManagement

enum LoginItemSettings {
  static var isEnabled: Bool {
    if #available(macOS 13.0, *) {
      return DaemonManager.snapshot().loginItem == .enabled
    }
    return false
  }

  static var needsApproval: Bool {
    if #available(macOS 13.0, *) {
      return DaemonManager.snapshot().needsApproval
    }
    return false
  }

  static func statusLabel() -> String {
    if #available(macOS 13.0, *) {
      return DaemonManager.statusLabel(DaemonManager.snapshot().loginItem)
    }
    return MacOSCompat.loginItemNote
  }

  @discardableResult
  static func ensureEnabled() -> String? {
    if #available(macOS 13.0, *) {
      return DaemonManager.registerAll()
    }
    return nil
  }

  static func openLoginItemsSettings() {
    if #available(macOS 13.0, *) {
      DaemonManager.openLoginItemsSettings()
    } else if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
      NSWorkspace.shared.open(url)
    }
  }
}
