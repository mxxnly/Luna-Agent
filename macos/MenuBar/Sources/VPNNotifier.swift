import AppKit
import UserNotifications

/// Banner notifications for *unexpected* VPN changes only.
/// Manual Connect/Disconnect is silent — the UI already shows the result.
enum VPNNotifier {
  private static let center = UNUserNotificationCenter.current()
  private static let defaultsKey = "luna.notifications.vpn"
  private static let suppressLock = NSLock()
  private static var suppressUntil: Date = .distantPast

  static var isEnabled: Bool {
    get {
      if UserDefaults.standard.object(forKey: defaultsKey) == nil { return true }
      return UserDefaults.standard.bool(forKey: defaultsKey)
    }
    set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
  }

  /// Call before user-initiated connect/disconnect so we don't spam a banner.
  static func suppressUserInitiated(for seconds: TimeInterval = 12) {
    suppressLock.lock()
    suppressUntil = Date().addingTimeInterval(seconds)
    suppressLock.unlock()
  }

  private static var isSuppressed: Bool {
    suppressLock.lock()
    defer { suppressLock.unlock() }
    return Date() < suppressUntil
  }

  static func requestPermissionIfNeeded() {
    center.getNotificationSettings { settings in
      guard settings.authorizationStatus == .notDetermined else { return }
      center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
  }

  /// Unexpected transition detected by status polling (not a button the user just pressed).
  static func unexpectedChange(nowUp: Bool, ip: String?) {
    guard isEnabled, !isSuppressed else { return }
    if nowUp {
      var body = "Tunnel came back online."
      if let ip, !ip.isEmpty { body = "Restored · \(ip)" }
      post(title: "VPN Restored", body: body, id: "vpn-restored")
    } else {
      post(
        title: "VPN Dropped",
        body: "Connection lost. LunaAgent will try to reconnect.",
        id: "vpn-dropped"
      )
    }
  }

  private static func post(title: String, body: String, id: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let req = UNNotificationRequest(
      identifier: "\(id)-\(Int(Date().timeIntervalSince1970))",
      content: content,
      trigger: nil
    )
    center.add(req, withCompletionHandler: nil)
  }
}
