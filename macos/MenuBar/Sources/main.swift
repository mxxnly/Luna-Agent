import AppKit
import Foundation

@main
struct LunaAgentMenuMain {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem?
  private let socketPath: String
  private let cookie: String

  override init() {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let data = "\(home)/Library/Application Support/LunaAgent"
    socketPath = ProcessInfo.processInfo.environment["LUNA_SOCKET"] ?? "\(data)/lunaagent.sock"
    if let env = ProcessInfo.processInfo.environment["LUNA_IPC_COOKIE"], !env.isEmpty {
      cookie = env
    } else {
      let cookieFile = "\(data)/ipc.cookie"
      cookie = (try? String(contentsOfFile: cookieFile, encoding: .utf8)) ?? ""
    }
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = item.button {
      button.title = "Luna"
      button.toolTip = "LunaAgent"
    }
    let menu = NSMenu()
    menu.addItem(NSMenuItem(title: "Status…", action: #selector(showStatus), keyEquivalent: "s"))
    menu.addItem(NSMenuItem(title: "Enroll…", action: #selector(enroll), keyEquivalent: "e"))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(NSMenuItem(title: "Connect VPN", action: #selector(vpnUp), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "Disconnect VPN", action: #selector(vpnDown), keyEquivalent: ""))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(NSMenuItem(title: "Copy Device ID", action: #selector(copyDeviceID), keyEquivalent: "c"))
    menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    item.menu = menu
    statusItem = item
  }

  @objc func showStatus() {
    let res = call(op: "status", args: [:])
    let alert = NSAlert()
    alert.messageText = "LunaAgent"
    if let data = res["data"] as? [String: Any] {
      alert.informativeText = "\(data)"
    } else {
      alert.informativeText = "\(res)"
    }
    alert.runModal()
  }

  @objc func enroll() {
    let url = prompt("Control Server URL", defaultText: "https://panel.example.com")
    let code = prompt("Enroll code", defaultText: "")
    guard let url, let code else { return }
    _ = call(op: "enroll", args: ["control_url": url, "enroll_code": code])
  }

  @objc func vpnUp() { _ = call(op: "vpn_up", args: [:]) }
  @objc func vpnDown() { _ = call(op: "vpn_down", args: [:]) }

  @objc func copyDeviceID() {
    let res = call(op: "status", args: [:])
    if let data = res["data"] as? [String: Any], let id = data["device_id"] as? String {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(id, forType: .string)
    }
  }

  private func prompt(_ title: String, defaultText: String) -> String? {
    let alert = NSAlert()
    alert.messageText = title
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
    field.stringValue = defaultText
    alert.accessoryView = field
    let resp = alert.runModal()
    guard resp == .alertFirstButtonReturn else { return nil }
    return field.stringValue
  }

  private func call(op: String, args: [String: Any]) -> [String: Any] {
    let sock = socketPath
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return ["ok": false, "error": "socket"] }
    defer { close(fd) }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = sock.utf8CString
    withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
      pathBytes.withUnsafeBufferPointer { src in
        let count = min(src.count, 104)
        for i in 0..<count {
          ptr.advanced(by: i).pointee = CChar(src[i])
        }
      }
    }
    let len = socklen_t(MemoryLayout<sockaddr_un>.size)
    let connected = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, len)
      }
    }
    guard connected == 0 else { return ["ok": false, "error": "connect"] }
    var body: [String: Any] = ["cookie": cookie, "op": op]
    if !args.isEmpty { body["args"] = args }
    guard let data = try? JSONSerialization.data(withJSONObject: body) else {
      return ["ok": false, "error": "encode"]
    }
    _ = data.withUnsafeBytes { raw in
      write(fd, raw.baseAddress, data.count)
    }
    var buf = [UInt8](repeating: 0, count: 65536)
    let n = read(fd, &buf, buf.count)
    guard n > 0 else { return ["ok": false, "error": "read"] }
    let respData = Data(buf[0..<n])
    return (try? JSONSerialization.jsonObject(with: respData) as? [String: Any]) ?? ["ok": false]
  }
}
