import AppKit
import Foundation
import ServiceManagement

/// Registers login item + user agent (lunaagentd) + root daemon (luna-wghelper).
/// SMAppService is preferred; ad-hoc signed builds fall back to user LaunchAgents
/// with absolute paths into /Applications/LunaAgent.app (codesign -67028 workaround).
/// The UI LaunchAgent is required so the menu bar returns after reboot when the
/// Login Item was never approved or SMAppService.mainApp did not stick.
@available(macOS 13.0, *)
enum DaemonManager {
  private static let agentPlist = "com.lunaagent.daemon.plist"
  private static let helperPlist = "com.lunaagent.wghelper.plist"
  private static let fallbackAgentLabel = "com.lunaagent.agent"
  private static let fallbackAgentPlistName = "com.lunaagent.agent.plist"
  private static let fallbackUILabel = "com.lunaagent.ui"
  private static let fallbackUIPlistName = "com.lunaagent.ui.plist"

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
    case .notFound:
      // Ad-hoc beta: SMAppService often reports notFound even from /Applications.
      return isRunningFromApplications()
        ? "Using LaunchAgent fallback (OK for beta)"
        : "Move app to /Applications"
    @unknown default: return "Unknown"
    }
  }

  /// True when this process is running from /Applications/LunaAgent.app (resolved).
  static func isRunningFromApplications() -> Bool {
    let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
    if path.hasPrefix("/Applications/LunaAgent.app") { return true }
    return FileManager.default.fileExists(atPath: "/Applications/LunaAgent.app")
      && path.hasPrefix("/Applications/")
  }

  /// Register services. Soft-fails SMAppService agent/helper on codesign errors (adhoc builds).
  /// Installs user LaunchAgent fallbacks once (idempotent) so reboot still starts UI + agent
  /// without re-triggering "Background Items Added" on every launch.
  @discardableResult
  static func registerAll() -> String? {
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
        softErrors.append("\(name): \(error.localizedDescription)")
        NSLog("LunaAgent SMAppService register soft-fail %@: %@", name, error.localizedDescription)
      }
    }

    // Beta / ad-hoc: SMApp Login Item often does not survive reboot. Fallbacks do.
    // Only rewrite launchd jobs when contents change — avoid Ventura+ notification spam.
    _ = installFallbackUserAgent()
    _ = installFallbackMenuBar()
    cleanupStaleUIHelperScript()

    // Only complain about location when the app really is not under /Applications.
    // Ad-hoc builds commonly leave SMAppService.mainApp as .notFound even when installed correctly.
    if !isRunningFromApplications() {
      return "Move LunaAgent to /Applications, then try again."
    }
    _ = softErrors
    return nil
  }

  @discardableResult
  static func unregisterAll() -> String? {
    var errors: [String] = []
    removeFallbackUserAgent()
    removeFallbackMenuBar()
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

  private static func launchAgentsDir() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
  }

  private static func fallbackAgentPlistURL() -> URL {
    launchAgentsDir().appendingPathComponent(fallbackAgentPlistName)
  }

  private static func fallbackUIPlistURL() -> URL {
    launchAgentsDir().appendingPathComponent(fallbackUIPlistName)
  }

  private static func supportDir() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/LunaAgent", isDirectory: true)
  }

  @discardableResult
  static func installFallbackUserAgent() -> String? {
    guard let bin = bundledAgentPath() else {
      return "lunaagentd missing inside LunaAgent.app — reinstall the beta pkg"
    }
    let wgDir: String = {
      let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/luna-wg").path
      if FileManager.default.fileExists(atPath: bundled) { return bundled }
      return "/Applications/LunaAgent.app/Contents/Resources/luna-wg"
    }()
    let logs = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Logs/LunaAgent", isDirectory: true).path
    try? FileManager.default.createDirectory(atPath: logs, withIntermediateDirectories: true)

    let plist: [String: Any] = [
      "Label": fallbackAgentLabel,
      "ProgramArguments": [bin],
      "RunAtLoad": true,
      "KeepAlive": true,
      "ThrottleInterval": 5,
      "ProcessType": "Background",
      // Group under LunaAgent in Login Items (avoids "lunaagentd" spam labels).
      "AssociatedBundleIdentifiers": ["com.lunaagent.app"],
      "EnvironmentVariables": [
        "PATH": "\(wgDir):/opt/homebrew/bin:/usr/local/bin:/usr/sbin:/sbin:/usr/bin:/bin",
      ],
      "StandardOutPath": "\(logs)/daemon.out.log",
      "StandardErrorPath": "\(logs)/daemon.err.log",
    ]

    return ensureLaunchAgent(plist: plist, url: fallbackAgentPlistURL(), label: fallbackAgentLabel)
  }

  /// Starts the menu bar app at login when SMAppService.mainApp did not stick.
  @discardableResult
  static func installFallbackMenuBar() -> String? {
    guard let script = bundledStartMenuBarPath() else {
      return "start-menubar.sh missing inside LunaAgent.app — reinstall the beta pkg"
    }

    let logs = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Logs/LunaAgent", isDirectory: true).path
    try? FileManager.default.createDirectory(atPath: logs, withIntermediateDirectories: true)

    // RunAtLoad + KeepAlive only on crash/non-zero exit. Do not re-bootstrap on every
    // app open (that re-fires "Background Items Added").
    let plist: [String: Any] = [
      "Label": fallbackUILabel,
      "ProgramArguments": [script],
      "RunAtLoad": true,
      "KeepAlive": ["SuccessfulExit": false],
      "ThrottleInterval": 10,
      "LimitLoadToSessionType": "Aqua",
      "ProcessType": "Interactive",
      "AssociatedBundleIdentifiers": ["com.lunaagent.app"],
      "StandardOutPath": "\(logs)/ui.out.log",
      "StandardErrorPath": "\(logs)/ui.err.log",
    ]
    return ensureLaunchAgent(plist: plist, url: fallbackUIPlistURL(), label: fallbackUILabel)
  }

  /// Prefer bundled Resources script; fall back to writing one next to the app binary path.
  private static func bundledStartMenuBarPath() -> String? {
    let fm = FileManager.default
    let candidates = [
      Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/start-menubar.sh").path,
      "/Applications/LunaAgent.app/Contents/Resources/start-menubar.sh",
    ]
    for path in candidates where fm.isExecutableFile(atPath: path) {
      return path
    }
    // Dev / older installs: materialize script beside Application Support once.
    guard bundledUIPath() != nil else { return nil }
    let support = supportDir()
    try? fm.createDirectory(at: support, withIntermediateDirectories: true)
    let script = support.appendingPathComponent("start-menubar.sh")
    let body = """
    #!/bin/bash
    set -euo pipefail
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
    APP="/Applications/LunaAgent.app"
    BIN="${APP}/Contents/MacOS/LunaAgent"
    if [[ ! -x "$BIN" ]]; then
      exit 0
    fi
    for _ in $(seq 1 60); do
      if pgrep -x Dock >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done
    sleep 3
    if pgrep -x LunaAgent >/dev/null 2>&1; then
      exit 0
    fi
    exec "$BIN"
    """
    do {
      try body.write(to: script, atomically: true, encoding: .utf8)
      try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
      return script.path
    } catch {
      return nil
    }
  }

  /// Write + bootstrap only when the plist changed or the job is not loaded.
  private static func ensureLaunchAgent(
    plist: [String: Any],
    url: URL,
    label: String
  ) -> String? {
    try? FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data: Data
    do {
      data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    } catch {
      return "Failed to serialize LaunchAgent: \(error.localizedDescription)"
    }

    let uid = getuid()
    let domain = "gui/\(uid)"
    let service = "\(domain)/\(label)"
    let existing = try? Data(contentsOf: url)
    let loaded = shell(["/bin/launchctl", "print", service]).status == 0

    if existing == data && loaded {
      return nil
    }

    do {
      try data.write(to: url, options: .atomic)
    } catch {
      return "Failed to write LaunchAgent: \(error.localizedDescription)"
    }

    if loaded {
      _ = shell(["/bin/launchctl", "bootout", service])
    }
    let boot = shell(["/bin/launchctl", "bootstrap", domain, url.path])
    _ = shell(["/bin/launchctl", "enable", service])
    if boot.status != 0 {
      // Already bootstrapped with same label after race — try kickstart only.
      _ = shell(["/bin/launchctl", "kickstart", "-k", service])
    } else {
      _ = shell(["/bin/launchctl", "kickstart", "-k", service])
    }
    NSLog("LunaAgent installed/updated LaunchAgent %@", label)
    return nil
  }

  static func removeFallbackUserAgent() {
    let uid = getuid()
    let domain = "gui/\(uid)"
    _ = shell(["/bin/launchctl", "bootout", "\(domain)/\(fallbackAgentLabel)"])
    try? FileManager.default.removeItem(at: fallbackAgentPlistURL())
  }

  static func removeFallbackMenuBar() {
    let uid = getuid()
    let domain = "gui/\(uid)"
    _ = shell(["/bin/launchctl", "bootout", "\(domain)/\(fallbackUILabel)"])
    try? FileManager.default.removeItem(at: fallbackUIPlistURL())
    cleanupStaleUIHelperScript()
  }

  /// Remove pre-0.2.16 Application Support start-ui.sh helper (showed as its own Background Item).
  private static func cleanupStaleUIHelperScript() {
    let support = supportDir()
    try? FileManager.default.removeItem(at: support.appendingPathComponent("start-ui.sh"))
    // Prefer bundled Resources script; drop old App Support copy when present in app.
    let bundled = "/Applications/LunaAgent.app/Contents/Resources/start-menubar.sh"
    if FileManager.default.isExecutableFile(atPath: bundled) {
      try? FileManager.default.removeItem(at: support.appendingPathComponent("start-menubar.sh"))
    }
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

  static func bundledUIPath() -> String? {
    let fm = FileManager.default
    let candidates = [
      Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/LunaAgent").path,
      "/Applications/LunaAgent.app/Contents/MacOS/LunaAgent",
    ]
    for path in candidates where fm.isExecutableFile(atPath: path) {
      return path
    }
    return nil
  }

  /// Remove pre-SMAppService /usr/local-style user agents (not our fallbacks).
  static func cleanupLegacyScatter() {
    let home = NSHomeDirectory()
    let menubar = "\(home)/Library/LaunchAgents/com.lunaagent.menubar.plist"
    try? FileManager.default.removeItem(atPath: menubar)
  }
}
