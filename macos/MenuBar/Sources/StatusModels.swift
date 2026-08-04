import Foundation

struct ProcessRow: Identifiable, Hashable {
  let id: Int
  let name: String
  let user: String
  let cpuPct: Double
  let ramBytes: Int64
}

struct AgentStatusSnapshot {
  var daemonReachable: Bool = false
  var ipcError: String?
  var enrolled: Bool = false
  var deviceID: String = ""
  var controlURL: String = ""
  var agentVersion: String = ""
  var lastError: String?
  var desiredVPN: String = ""
  var vpnState: String = "down"
  var internalIP: String?
  var hostname: String = ""
  var model: String = ""
  var serial: String = ""
  var hardwareUUID: String = ""
  var osVersion: String = ""
  var username: String = ""
  var cpuPct: Double = 0
  var ramPct: Double = 0
  var diskPct: Double = 0
  var ramUsed: Int64 = 0
  var ramTotal: Int64 = 0
  var diskUsed: Int64 = 0
  var diskTotal: Int64 = 0
  var hasWGConfig: Bool = false
  var tunnelMode: String = "live"
  var topCPU: [ProcessRow] = []
  var topRAM: [ProcessRow] = []
  var collectedAt: String = ""
  var adminConfigured: Bool = false
  var adminUnlocked: Bool = false
  /// Seconds left in admin unlock window; 0 when locked / not configured.
  var adminUnlockedRemaining: Int = 0

  /// Sensitive local actions need admin unlock when configured.
  var needsAdminUnlock: Bool { adminConfigured && !adminUnlocked }

  static func from(response: [String: Any]) -> AgentStatusSnapshot {
    var s = AgentStatusSnapshot()
    if let err = response["error"] as? String {
      s.daemonReachable = false
      s.ipcError = err
      return s
    }
    guard (response["ok"] as? Bool) == true, let data = response["data"] as? [String: Any] else {
      s.daemonReachable = false
      s.ipcError = (response["error"] as? String) ?? "bad_response"
      return s
    }
    s.daemonReachable = true
    if let conn = data["connection"] as? [String: Any] {
      s.enrolled = (conn["enrolled"] as? Bool) ?? false
      s.deviceID = (conn["device_id"] as? String) ?? ""
      s.controlURL = (conn["control_url"] as? String) ?? ""
      s.agentVersion = (conn["agent_version"] as? String) ?? ""
      s.lastError = conn["last_error"] as? String
      s.desiredVPN = (conn["desired_vpn_state"] as? String) ?? ""
    } else {
      s.enrolled = (data["enrolled"] as? Bool) ?? false
      s.deviceID = (data["device_id"] as? String) ?? ""
      s.controlURL = (data["control_url"] as? String) ?? ""
      s.agentVersion = (data["version"] as? String) ?? ""
      s.lastError = data["last_error"] as? String
    }
    if let device = data["device"] as? [String: Any] {
      s.hostname = (device["hostname"] as? String) ?? ""
      s.model = (device["model"] as? String) ?? ""
      s.serial = (device["serial"] as? String) ?? ""
      s.hardwareUUID = (device["hardware_uuid"] as? String) ?? ""
      s.osVersion = (device["os_version"] as? String) ?? ""
      s.username = (device["username"] as? String) ?? ""
    }
    if let vpn = data["vpn"] as? [String: Any] {
      s.vpnState = (vpn["state"] as? String) ?? "down"
      s.internalIP = vpn["internal_ip"] as? String
      s.hasWGConfig = (vpn["has_config"] as? Bool) ?? false
      s.tunnelMode = (vpn["mode"] as? String) ?? "live"
    } else {
      s.vpnState = ((data["vpn_up"] as? Bool) == true) ? "up" : "down"
      s.internalIP = data["internal_ip"] as? String
    }
    if let metrics = data["metrics"] as? [String: Any] {
      s.cpuPct = doubleVal(metrics["cpu_pct"])
      s.ramUsed = int64Val(metrics["ram_used_bytes"])
      s.ramTotal = int64Val(metrics["ram_total_bytes"])
      s.diskUsed = int64Val(metrics["disk_used_bytes"])
      s.diskTotal = int64Val(metrics["disk_total_bytes"])
      s.ramPct = doubleVal(metrics["ram_pct"])
      s.diskPct = doubleVal(metrics["disk_pct"])
      if s.ramPct <= 0 { s.ramPct = pct(s.ramUsed, s.ramTotal) }
      if s.diskPct <= 0 { s.diskPct = pct(s.diskUsed, s.diskTotal) }
      s.topCPU = parseProcesses(metrics["top_cpu"])
      s.topRAM = parseProcesses(metrics["top_ram"])
    }
    s.collectedAt = (data["collected_at"] as? String) ?? ""
    if let admin = data["admin"] as? [String: Any] {
      s.adminConfigured = (admin["configured"] as? Bool) ?? false
      s.adminUnlocked = (admin["unlocked"] as? Bool) ?? false
      if let rem = admin["unlocked_remaining_seconds"] as? Int {
        s.adminUnlockedRemaining = max(0, rem)
      } else if let n = admin["unlocked_remaining_seconds"] as? NSNumber {
        s.adminUnlockedRemaining = max(0, n.intValue)
      } else {
        s.adminUnlockedRemaining = s.adminUnlocked ? 600 : 0
      }
    }
    return s
  }

  private static func doubleVal(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let n = v as? NSNumber { return n.doubleValue }
    return 0
  }

  private static func pct(_ used: Int64, _ total: Int64) -> Double {
    guard total > 0 else { return 0 }
    return min(100, max(0, 100 * Double(used) / Double(total)))
  }

  private static func int64Val(_ v: Any?) -> Int64 {
    if let i = v as? Int64 { return i }
    if let i = v as? Int { return Int64(i) }
    if let n = v as? NSNumber { return n.int64Value }
    return 0
  }

  private static func parseProcesses(_ v: Any?) -> [ProcessRow] {
    guard let arr = v as? [[String: Any]] else { return [] }
    return arr.compactMap { row in
      let pid = (row["pid"] as? Int) ?? (row["pid"] as? NSNumber)?.intValue ?? 0
      let name = (row["name"] as? String) ?? ""
      let user = (row["user"] as? String) ?? ""
      let cpu = doubleVal(row["cpu_pct"])
      let ram = int64Val(row["ram_bytes"])
      return ProcessRow(id: pid, name: name, user: user, cpuPct: cpu, ramBytes: ram)
    }
  }
}
