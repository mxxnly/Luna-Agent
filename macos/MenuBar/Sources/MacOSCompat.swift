import Foundation

enum MacOSCompat {
  static var versionString: String {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
  }

  static var isFullUI: Bool {
    if #available(macOS 13.0, *) { return true }
    return false
  }

  /// Short banner for UI.
  static var modeBanner: String {
    if isFullUI {
      return "Full UI · macOS \(versionString) (complete features from macOS 13+)"
    }
    return "Compatibility mode · macOS \(versionString) — basic features only. Full UI requires macOS 13+"
  }

  static var loginItemNote: String {
    if #available(macOS 13.0, *) {
      return "Background services via SMAppService (macOS 13+)"
    }
    return "Legacy: LaunchAgents from the Legacy pkg (macOS 10.14–12)."
  }

  static var featureLines: [String] {
    [
      "Full menu UI: macOS 13+",
      "Login Item API: macOS 13+",
      "Basic enroll / VPN / WG conf: macOS 10.14+",
      "Notifications: macOS 10.14+",
      "Daemon + WireGuard helper: macOS 10.14+",
    ]
  }
}
