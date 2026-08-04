import AppKit
import Combine
import Foundation

extension Notification.Name {
  static let lunaAgentStatusDidChange = Notification.Name("lunaAgentStatusDidChange")
}

@available(macOS 13.0, *)
final class StatusViewModel: ObservableObject {
  @Published var snapshot = AgentStatusSnapshot()
  @Published var enrollURL: String = "http://91.99.71.184"
  @Published var enrollCode: String = ""
  @Published var enrollMessage: String?
  @Published var enrollOK: Bool?
  @Published var actionMessage: String?
  @Published var startingDaemon = false
  @Published var wgConfText: String = ""
  @Published var wgMessage: String?
  @Published var wgOK: Bool?
  @Published var busy = false
  @Published var busyLabel = ""
  /// Desired VPN while an operation is in flight (optimistic UI).
  @Published var pendingVPN: Bool?
  @Published var vpnNotificationsEnabled = VPNNotifier.isEnabled
  @Published var adminPassword: String = ""
  @Published var adminUnlockMessage: String?
  @Published var showAdminUnlock = false

  /// When true, next polls include heavy metrics.
  var wantMetrics = false

  private let ipc = IPCClient()
  private let ipcQueue = DispatchQueue(label: "com.lunaagent.ipc", qos: .userInitiated)
  private var timer: Timer?
  private var refreshGeneration = 0

  func startPolling() {
    ensureDaemonThenRefresh()
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
      self?.refreshAsync(light: !(self?.wantMetrics ?? false))
    }
  }

  func stopPolling() {
    timer?.invalidate()
    timer = nil
  }

  func ensureDaemonThenRefresh() {
    startingDaemon = true
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let err = DaemonLauncher.ensureRunning()
      DispatchQueue.main.async {
        self?.startingDaemon = false
        if let err {
          self?.actionMessage = err
        }
        self?.refreshAsync(light: false)
      }
    }
  }

  func refresh() {
    refreshAsync(light: !wantMetrics)
  }

  func refreshAsync(light: Bool) {
    if busy { return }
    refreshGeneration += 1
    let gen = refreshGeneration
    ipcQueue.async { [weak self] in
      guard let self else { return }
      var args: [String: Any] = [:]
      if light { args["light"] = true }
      let res = self.ipc.call(op: "status", args: args)
      let snap = AgentStatusSnapshot.from(response: res)
      DispatchQueue.main.async {
        guard gen == self.refreshGeneration, !self.busy else { return }
        // Preserve last metrics if this was a light poll.
        if light, self.snapshot.ramTotal > 0 || !self.snapshot.topCPU.isEmpty {
          var merged = snap
          if snap.ramTotal == 0 {
            merged.cpuPct = self.snapshot.cpuPct
            merged.ramPct = self.snapshot.ramPct
            merged.diskPct = self.snapshot.diskPct
            merged.ramUsed = self.snapshot.ramUsed
            merged.ramTotal = self.snapshot.ramTotal
            merged.diskUsed = self.snapshot.diskUsed
            merged.diskTotal = self.snapshot.diskTotal
            merged.topCPU = self.snapshot.topCPU
            merged.topRAM = self.snapshot.topRAM
          }
          self.snapshot = merged
        } else {
          self.snapshot = snap
        }
      }
    }
  }

  func setVPN(_ on: Bool) {
    if on { vpnUp() } else { vpnDown() }
  }

  func vpnUp() {
    VPNNotifier.suppressUserInitiated()
    runBusy(label: "Connecting VPN…", allowOverlap: true) { ipc in
      ipc.call(op: "vpn_up")
    } done: { [weak self] res in
      let ok = (res["ok"] as? Bool) == true
      self?.actionMessage = ok ? nil : self?.friendlyError(res)
      self?.wgMessage = ok ? nil : self?.friendlyError(res)
      self?.wgOK = ok
      NotificationCenter.default.post(name: .lunaAgentStatusDidChange, object: nil)
    }
  }

  func vpnDown() {
    VPNNotifier.suppressUserInitiated()
    runBusy(label: "Disconnecting VPN…", allowOverlap: true) { ipc in
      ipc.call(op: "vpn_down")
    } done: { [weak self] res in
      let ok = (res["ok"] as? Bool) == true
      self?.actionMessage = ok ? nil : self?.friendlyError(res)
      self?.wgMessage = ok ? nil : self?.friendlyError(res)
      self?.wgOK = ok
      NotificationCenter.default.post(name: .lunaAgentStatusDidChange, object: nil)
    }
  }

  func promptAdminUnlock(_ message: String) {
    adminUnlockMessage = message
    showAdminUnlock = true
  }

  func setVPNNotifications(_ on: Bool) {
    VPNNotifier.isEnabled = on
    vpnNotificationsEnabled = on
    if on {
      VPNNotifier.requestPermissionIfNeeded()
      actionMessage = "Drop/restore alerts on"
    } else {
      actionMessage = "Drop/restore alerts off"
    }
  }

  func refreshPrefs() {
    vpnNotificationsEnabled = VPNNotifier.isEnabled
  }

  var isAdminLocked: Bool {
    snapshot.adminConfigured && !snapshot.adminUnlocked
  }

  func requireAdmin(then action: @escaping () -> Void) {
    if !isAdminLocked {
      action()
      return
    }
    showAdminUnlock = true
    adminUnlockMessage = "Admin password required"
    // Stash is awkward — caller should open unlock sheet then retry.
  }

  func adminUnlock() {
    let pass = adminPassword
    guard !pass.isEmpty else {
      adminUnlockMessage = "Enter admin password"
      return
    }
    runBusy(label: "Unlocking…") { ipc in
      ipc.call(op: "admin_unlock", args: ["password": pass])
    } done: { [weak self] res in
      if (res["ok"] as? Bool) == true {
        self?.adminPassword = ""
        self?.adminUnlockMessage = "Unlocked for 10 minutes"
        self?.showAdminUnlock = false
        self?.refreshAsync(light: true)
      } else {
        let err = (res["error"] as? String) ?? "unlock failed"
        self?.adminUnlockMessage = err == "bad_password" ? "Wrong password" : err
      }
    }
  }

  func adminLockNow() {
    ipcQueue.async { [weak self] in
      _ = self?.ipc.call(op: "admin_lock")
      DispatchQueue.main.async {
        self?.refreshAsync(light: true)
        self?.actionMessage = "Admin locked"
      }
    }
  }

  func pasteWGConfig() {
    if let s = NSPasteboard.general.string(forType: .string)?
      .trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
      wgConfText = s
    }
  }

  /// Loads saved WireGuard conf from the daemon into the editor field.
  func loadSavedWGConfig(completion: (() -> Void)? = nil) {
    ipcQueue.async { [weak self] in
      guard let self else { return }
      let res = self.ipc.call(op: "get_wg_config")
      let text: String
      if (res["ok"] as? Bool) == true, let data = res["data"] as? [String: Any] {
        text = (data["conf_text"] as? String) ?? ""
      } else {
        text = ""
      }
      DispatchQueue.main.async {
        // Keep unsaved paste if editor already has different text and no saved conf.
        if !text.isEmpty {
          self.wgConfText = text
          self.wgMessage = nil
          self.wgOK = nil
        } else if self.wgConfText.isEmpty {
          self.wgMessage = nil
        }
        completion?()
      }
    }
  }

  func applyWGConfig(connect: Bool) {
    let conf = wgConfText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !conf.isEmpty else {
      wgOK = false
      wgMessage = "Paste a WireGuard .conf first"
      return
    }
    if connect { VPNNotifier.suppressUserInitiated() }
    let label = connect ? "Saving & connecting…" : "Saving config…"
    runBusy(label: label) { ipc in
      ipc.call(op: "apply_wg_config", args: [
        "conf_text": conf,
        "connect": connect,
      ])
    } done: { [weak self] res in
      if (res["ok"] as? Bool) == true {
        self?.wgOK = true
        self?.wgMessage = connect ? "Config saved and VPN connected" : "Config saved"
      } else if (res["error"] as? String) == "admin_locked" {
        self?.wgOK = false
        self?.promptAdminUnlock("Admin password required to edit config")
      } else {
        self?.wgOK = false
        self?.wgMessage = self?.friendlyError(res)
      }
      NotificationCenter.default.post(name: .lunaAgentStatusDidChange, object: nil)
    }
  }

  func copyDeviceID() {
    let id = snapshot.deviceID
    guard !id.isEmpty else {
      actionMessage = "No device ID yet — enroll first"
      return
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(id, forType: .string)
    actionMessage = "Device ID copied"
  }

  func pasteEnrollCode() {
    if let s = NSPasteboard.general.string(forType: .string)?
      .trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
      enrollCode = s
    }
  }

  func pasteEnrollURL() {
    if let s = NSPasteboard.general.string(forType: .string)?
      .trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
      enrollURL = s
    }
  }

  func enroll() {
    let url = enrollURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let code = enrollCode.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !url.isEmpty, !code.isEmpty else {
      enrollOK = false
      enrollMessage = "Enter control URL and enroll code"
      return
    }
    runBusy(label: "Enrolling…") { ipc in
      ipc.call(op: "enroll", args: ["control_url": url, "enroll_code": code])
    } done: { [weak self] res in
      if (res["ok"] as? Bool) == true {
        self?.enrollOK = true
        self?.enrollMessage = "Enrolled — check Devices on the control panel"
        self?.enrollCode = ""
      } else if (res["error"] as? String) == "admin_locked" {
        self?.enrollOK = false
        self?.promptAdminUnlock("Admin password required to enroll")
      } else {
        self?.enrollOK = false
        self?.enrollMessage = self?.friendlyError(res)
      }
    }
  }

  func unenroll() {
    if isAdminLocked {
      promptAdminUnlock("Admin password required to unenroll")
      return
    }
    runBusy(label: "Unenrolling…") { ipc in
      ipc.call(op: "unenroll")
    } done: { [weak self] res in
      if (res["ok"] as? Bool) == true {
        self?.actionMessage = "Unenrolled — local link cleared"
        self?.enrollOK = nil
        self?.enrollMessage = nil
      } else if (res["error"] as? String) == "admin_locked" {
        self?.promptAdminUnlock("Admin password required to unenroll")
      } else {
        self?.actionMessage = self?.friendlyError(res)
      }
      NotificationCenter.default.post(name: .lunaAgentStatusDidChange, object: nil)
    }
  }

  private func runBusy(
    label: String,
    allowOverlap: Bool = false,
    work: @escaping (IPCClient) -> [String: Any],
    done: @escaping ([String: Any]) -> Void
  ) {
    if busy && !allowOverlap { return }
    busy = true
    busyLabel = label
    if label.contains("Connecting") {
      pendingVPN = true
    } else if label.contains("Disconnecting") {
      pendingVPN = false
    } else if label.contains("connecting") {
      pendingVPN = true
    }

    ipcQueue.async { [weak self] in
      guard let self else { return }
      let res = work(self.ipc)
      // Quick status after op
      let status = self.ipc.call(op: "status", args: ["light": true])
      let snap = AgentStatusSnapshot.from(response: status)
      DispatchQueue.main.async {
        self.busy = false
        self.busyLabel = ""
        self.pendingVPN = nil
        if (status["ok"] as? Bool) == true {
          // Keep previous metrics
          var merged = snap
          if self.snapshot.ramTotal > 0 {
            merged.cpuPct = self.snapshot.cpuPct
            merged.ramPct = self.snapshot.ramPct
            merged.diskPct = self.snapshot.diskPct
            merged.ramUsed = self.snapshot.ramUsed
            merged.ramTotal = self.snapshot.ramTotal
            merged.diskUsed = self.snapshot.diskUsed
            merged.diskTotal = self.snapshot.diskTotal
            merged.topCPU = self.snapshot.topCPU
            merged.topRAM = self.snapshot.topRAM
          }
          self.snapshot = merged
        }
        done(res)
        if self.wantMetrics {
          self.refreshAsync(light: false)
        }
      }
    }
  }

  private func friendlyError(_ res: [String: Any]) -> String {
    let err = (res["error"] as? String) ?? "\(res)"
    if err == "connect" || err == "socket" {
      return "Agent service offline — tap Start agent"
    }
    if err == "unauthorized" {
      return "IPC auth failed — restart LunaAgent"
    }
    if err == "admin_locked" {
      return "Admin password required"
    }
    if err == "bad_password" {
      return "Wrong admin password"
    }
    return err
  }
}
