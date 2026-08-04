import Foundation

/// Installed app / agent version shown in UI and Prefer daemon IPC when available.
enum AppVersion {
  /// CFBundleShortVersionString from the installed .app (set by the installer).
  static var bundleShort: String {
    let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let trimmed = (v ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "dev" : trimmed
  }

  static var displayName: String { "LunaAgent \(bundleShort)" }

  /// Prefer live daemon version from IPC; fall back to bundle.
  static func resolved(daemon: String) -> String {
    let d = daemon.trimmingCharacters(in: .whitespacesAndNewlines)
    if !d.isEmpty { return d }
    return bundleShort
  }
}
