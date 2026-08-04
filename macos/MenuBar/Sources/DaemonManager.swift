import AppKit
import Foundation
import ServiceManagement

/// Registers login item + user agent (lunaagentd) + root daemon (luna-wghelper) via SMAppService.
@available(macOS 13.0, *)
enum DaemonManager {
  private static let agentPlist = "com.lunaagent.daemon.plist"
  private static let helperPlist = "com.lunaagent.wghelper.plist"

  struct StatusSnapshot {
    var loginItem: SMAppService.Status
    var agent: SMAppService.Status
    var helper: SMAppService.Status

    var allEnabled: Bool {
      loginItem == .enabled && agent == .enabled && helper == .enabled
    }

    var needsApproval: Bool {
      [loginItem, agent, helper].contains(.requiresApproval)
    }

    var notFound: Bool {
      [loginItem, agent, helper].contains(.notFound)
    }
  }

  static var loginItemService: SMAppService { .mainApp }
  static var agentService: SMAppService { .agent(plistName: agentPlist) }
  static var helperService: SMAppService { .daemon(plistName: helperPlist) }

  static func snapshot() -> StatusSnapshot {
    StatusSnapshot(
      loginItem: loginItemService.status,
      agent: agentService.status,
      helper: helperService.status
    )
  }

  static func statusLabel(_ s: SMAppService.Status) -> String {
    switch s {
    case .enabled: return "Enabled"
    case .requiresApproval: return "Needs approval in System Settings"
    case .notRegistered: return "Not registered"
    case .notFound: return "Unavailable — keep app in /Applications"
    @unknown default: return "Unknown"
    }
  }

  /// Register all three services. Returns a user-visible error string, or nil on success / pending approval.
  @discardableResult
  static func registerAll() -> String? {
    var errors: [String] = []
    for (name, service) in [
      ("Login item", loginItemService),
      ("Background agent", agentService),
      ("WireGuard helper", helperService),
    ] as [(String, SMAppService)] {
      switch service.status {
      case .enabled, .requiresApproval:
        continue
      default:
        break
      }
      do {
        try service.register()
      } catch {
        errors.append("\(name): \(error.localizedDescription)")
      }
    }
    if snapshot().notFound {
      return "Move LunaAgent to /Applications, then try again."
    }
    if errors.isEmpty { return nil }
    return errors.joined(separator: "\n")
  }

  @discardableResult
  static func unregisterAll() -> String? {
    var errors: [String] = []
    for service in [helperService, agentService, loginItemService] {
      do {
        try service.unregister()
      } catch {
        errors.append(error.localizedDescription)
      }
    }
    if errors.isEmpty { return nil }
    return errors.joined(separator: "\n")
  }

  static func openLoginItemsSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
      NSWorkspace.shared.open(url)
    }
  }

  /// Ensure services are registered, then wait briefly for agent IPC.
  static func ensureRunning(ipcPing: () -> Bool) -> String? {
    if let err = registerAll() { return err }
    if snapshot().needsApproval {
      return "Approve LunaAgent in System Settings → General → Login Items & Extensions, then reopen."
    }
    for _ in 0..<30 {
      if ipcPing() { return nil }
      Thread.sleep(forTimeInterval: 0.2)
    }
    // Fallback: spawn bundled agent once if SMAppService has not started it yet.
    if let err = spawnBundledAgentIfNeeded(ipcPing: ipcPing) {
      return err
    }
    return nil
  }

  private static func spawnBundledAgentIfNeeded(ipcPing: () -> Bool) -> String? {
    if ipcPing() { return nil }
    guard let bin = bundledAgentPath() else {
      return "lunaagentd missing inside LunaAgent.app — reinstall the beta pkg"
    }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: bin)
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    do {
      try task.run()
    } catch {
      return "Failed to start agent: \(error.localizedDescription)"
    }
    for _ in 0..<20 {
      Thread.sleep(forTimeInterval: 0.15)
      if ipcPing() { return nil }
    }
    return "Agent started but IPC not ready yet"
  }

  static func bundledAgentPath() -> String? {
    let fm = FileManager.default
    let candidates = [
      Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/lunaagentd").path,
      "/Applications/LunaAgent.app/Contents/MacOS/lunaagentd",
    ]
    for path in candidates where fm.isExecutableFile(atPath: path) {
      return path
    }
    return nil
  }

  /// Best-effort removal of pre-SMAppService scatter installs (user LaunchAgents).
  static func cleanupLegacyScatter() {
    let home = NSHomeDirectory()
    let userAgents = [
      "\(home)/Library/LaunchAgents/com.lunaagent.daemon.plist",
      "\(home)/Library/LaunchAgents/com.lunaagent.menubar.plist",
    ]
    for path in userAgents {
      try? FileManager.default.removeItem(atPath: path)
    }
  }
}
