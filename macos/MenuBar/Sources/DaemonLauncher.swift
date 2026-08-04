import AppKit
import Foundation

enum DaemonLauncher {
  /// Prefer SMAppService (macOS 13+); fall back to spawning the bundled agent.
  static func ensureRunning() -> String? {
    let ipc = IPCClient()
    if ipc.ping() { return nil }

    if #available(macOS 13.0, *) {
      return DaemonManager.ensureRunning(ipcPing: { ipc.ping() })
    }

    guard let bin = resolveBinary() else {
      return "lunaagentd not found — reinstall LunaAgent (Legacy) pkg"
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
      return "Failed to start daemon: \(error.localizedDescription)"
    }

    for _ in 0..<20 {
      Thread.sleep(forTimeInterval: 0.15)
      if ipc.ping() { return nil }
    }
    return "Daemon started but IPC not ready yet"
  }

  private static func resolveBinary() -> String? {
    let fm = FileManager.default
    let candidates = [
      Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/lunaagentd").path,
      "/Applications/LunaAgent.app/Contents/MacOS/lunaagentd",
      "/usr/local/bin/lunaagentd", // legacy migration
    ]
    for path in candidates where fm.isExecutableFile(atPath: path) {
      return path
    }
    return nil
  }
}
