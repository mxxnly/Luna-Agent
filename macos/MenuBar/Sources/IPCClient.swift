import Foundation

final class IPCClient {
  let socketPath: String
  private let fixedCookie: String?

  init(socketPath: String? = nil, cookie: String? = nil) {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let data = "\(home)/Library/Application Support/LunaAgent"
    self.socketPath = socketPath
      ?? ProcessInfo.processInfo.environment["LUNA_SOCKET"]
      ?? "\(data)/lunaagent.sock"
    if let cookie, !cookie.isEmpty {
      self.fixedCookie = cookie
    } else if let env = ProcessInfo.processInfo.environment["LUNA_IPC_COOKIE"], !env.isEmpty {
      self.fixedCookie = env
    } else {
      self.fixedCookie = nil
    }
  }

  private var dataDir: String {
    (socketPath as NSString).deletingLastPathComponent
  }

  private func currentCookie() -> String {
    if let fixedCookie { return fixedCookie }
    let cookieFile = (dataDir as NSString).appendingPathComponent("ipc.cookie")
    return (try? String(contentsOfFile: cookieFile, encoding: .utf8))?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  func ping() -> Bool {
    let res = call(op: "status")
    return (res["ok"] as? Bool) == true
  }

  func call(op: String, args: [String: Any] = [:]) -> [String: Any] {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return ["ok": false, "error": "socket"] }
    defer { close(fd) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = socketPath.utf8CString
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

    var body: [String: Any] = ["cookie": currentCookie(), "op": op]
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
