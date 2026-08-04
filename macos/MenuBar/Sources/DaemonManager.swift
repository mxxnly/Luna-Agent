import AppKit
import Foundation
import ServiceManagement

/// Registers login item + user agent (lunaagentd) + root daemon (luna-wghelper).
/// SMAppService is preferred; ad-hoc signed builds fall back to a user LaunchAgent
/// with an absolute path into /Applications/LunaAgent.app (codesign -67028 workaround).
@available(macOS 13.0, *)
enum DaemonManager {
  private static let agentPlist = "com.lunaagent.daemon.plist"
  private static let helperPlist = "com.lunaagent.wghelper.plist"
  private static let fallbackAgentLabel = "com.lunaagent.agent"
  private static let fallbackAgentPlistName = "com.lunaagent.agent.plist"

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

    var agentReadyViaSMApp: Bool {
      agent == .enabled || agent == .requiresApproval
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

  /// Register services. Soft-fails SMAppService agent/helper on codesign errors (adhoc builds).
  @discardableResult
  static func registerAll() -> String? {
    // Login item usually works even on adhoc.
    if loginItemService.status != .enabled && loginItemService.status != .requiresApproval {
      do { try loginItemService.register() } catch {
        NSLog("LunaAgent login item register: %@", error.localizedDescription)
      }
    }

    var softErrors: [String] = []
    for (name, service) in [
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
        // -67028 / SMAppServiceErrorDomain Code=3: adhoc signature cannot load BundleProgram plists.
        softErrors.append("\(name): \(error.localizedDescription)")
        NSLog("LunaAgent SMAppService register soft-fail %@: %@", name, error.localizedDescription)
      }
    }

    if snapshot().loginItem == .notFound {
      return "Move LunaAgent to /Applications, then try again."
    }
    // Do not hard-fail on agent/helper SMAppService errors — fallback LaunchAgent handles agent.
    _ = softErrors
    return nil
  }

  @discardableResult
  static func unregisterAll() -> String? {
    var errors: [String] = []
    removeFallbackUserAgent()
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

  /// Ensure agent IPC is up: SMAppService → user LaunchAgent fallback → one-shot spawn.
  static func ensureRunning(ipcPing: () -> Bool) -> String? {
    cleanupLegacyScatter()
    _ = registerAll()

    if snapshot().needsApproval && snapshot().agent == .requiresApproval {
      // Still try fallback/spawn so UI works while user approves.
      NSLog("LunaAgent agent requires approval — using fallback start")
    }

    for _ in 0..<20 {
      if ipcPing() { return nil }
      Thread.sleep(forTimeInterval: 0.15)
    }

    if !snapshot().agentReadyViaSMApp {
      _ = installFallbackUserAgent()
      for _ in 0..<20 {
        if ipcPing() { return nil }
        Thread.sleep(forTimeInterval: 0.15)
      }
    }

    if let err = spawnBundledAgentIfNeeded(ipcPing: ipcPing) {
      return err
    }
    return nil
  }

  private static func fallbackAgentPlistURL() -> URL {
    let dir = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    return dir.appendingPathComponent(fallbackAgentPlistName)
  }

  /// Classic LaunchAgent with absolute path — works without Developer ID.
  @discardableResult
  static func installFallbackUserAgent() -> String? {
    guard let bin = bundledAgentPath() else {
      return "lunaagentd missing inside LunaAgent.app — reinstall the beta pkg"
    }
    let wg = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/luna-wg").path
    let support = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/LunaAgent", isDirectory: true).path
    let logs = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Logs/LunaAgent", isDirectory: true).path
    try? FileManager.default.createDirectory(atPath: support, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(atPath: logs, withIntermediateDirectories: true)

    let plist: [String: Any] = [
      "Label": fallbackAgentLabel,
      "ProgramArguments": [bin],
      "RunAtLoad": true,
      "KeepAlive": true,
      "ThrottleInterval": 5,
      "ProcessType": "Background",
      "EnvironmentVariables": [
        "PATH": "\(wg):/opt/homebrew/bin:/usr/local/bin:/usr/sbin:/sbin:/usr/bin:/bin",
      ],
      "StandardOutPath": "\(logs)/daemon.out.log",
      "StandardErrorPath": "\(logs)/daemon.err.log",
    ]

    let url = fallbackAgentPlistURL()
    try? FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    do {
      let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
      try data.write(to: url, options: .atomic)
    } catch {
      return "Failed to write LaunchAgent: \(error.localizedDescription)"
    }

    let uid = getuid()
    let domain = "gui/\(uid)"
    // Replace any stale definition (including deleted /usr/local jobs).
    _ = shell(["/bin/launchctl", "bootout", "\(domain)/\(fallbackAgentLabel)"])
    let boot = shell(["/bin/launchctl", "bootstrap", domain, url.path])
    if boot.status != 0 {
      // Already loaded — kickstart
      _ = shell(["/bin/launchctl", "enable", "\(domain)/\(fallbackAgentLabel)"])
      _ = shell(["/bin/launchctl", "kickstart", "-k", "\(domain)/\(fallbackAgentLabel)"])
    } else {
      _ = shell(["/bin/launchctl", "enable", "\(domain)/\(fallbackAgentLabel)"])
      _ = shell(["/bin/launchctl", "kickstart", "-k", "\(domain)/\(fallbackAgentLabel)"])
    }
    NSLog("LunaAgent installed fallback LaunchAgent -> %@", bin)
    return nil
  }

  static func removeFallbackUserAgent() {
    let uid = getuid()
    let domain = "gui/\(uid)"
    _ = shell(["/bin/launchctl", "bootout", "\(domain)/\(fallbackAgentLabel)"])
    try? FileManager.default.removeItem(at: fallbackAgentPlistURL())
  }

  private static func shell(_ args: [String]) -> (status: Int32, output: String) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: args[0])
    task.arguments = Array(args.dropFirst())
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    do {
      try task.run()
      task.waitUntilExit()
    } catch {
      return (1, error.localizedDescription)
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
  }

  private static func spawnBundledAgentIfNeeded(ipcPing: () -> Bool) -> String? {
    if ipcPing() { return nil }
    guard let bin = bundledAgentPath() else {
      return "lunaagentd missing inside LunaAgent.app — reinstall the beta pkg"
    }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: bin)
    var env = ProcessInfo.processInfo.environment
    let wg = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/luna-wg").path
    let prefix = "\(wg):/opt/homebrew/bin:/usr/local/bin:/usr/sbin:/sbin"
    if let path = env["PATH"], !path.isEmpty {
      env["PATH"] = prefix + ":" + path
    } else {
      env["PATH"] = prefix + ":/usr/bin:/bin"
    }
    task.environment = env
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    do {
      try task.run()
    } catch {
      return "Failed to start agent: \(error.localizedDescription)"
    }
    for _ in 0..<25 {
      Thread.sleep(forTimeInterval: 0.15)
      if ipcPing() { return nil }
    }
    return "Agent started but IPC not ready yet — open Finish setup again"
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

  /// Remove pre-SMAppService /usr/local-style user agents (not our fallback).
  static func cleanupLegacyScatter() {
    // Keep our intentional fallback plist; only remove menubar scatter leftovers.
    let home = NSHomeDirectory()
    let menubar = "\(home)/Library/LaunchAgents/com.lunaagent.menubar.plist"
    try? FileManager.default.removeItem(atPath: menubar)
  }
}
