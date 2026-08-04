import AppKit

/// Minimal AppKit UI for macOS 10.14–12 (basic enroll / VPN / WG).
final class BasicAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private var statusItem: NSStatusItem?
  private var window: NSWindow?
  private let ipc = IPCClient()
  private var timer: Timer?

  private var bannerLabel: NSTextField!
  private var statusLabel: NSTextField!
  private var enrollURLField: NSTextField!
  private var enrollCodeField: NSTextField!
  private var confView: NSTextView!
  private var busy = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSLog("LunaAgent compat mode os=%@ — basic UI (full UI needs macOS 13+)", MacOSCompat.versionString)
    installMenu()
    VPNNotifier.requestPermissionIfNeeded()
    DispatchQueue.global(qos: .utility).async {
      _ = DaemonLauncher.ensureRunning()
      Thread.sleep(forTimeInterval: 0.6)
      DispatchQueue.main.async { self.refreshStatus() }
    }

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = item.button {
      button.image = BrandAssets.menuBarImage(state: .idle)
      button.image?.isTemplate = true
      button.target = self
      button.action = #selector(toggleWindow)
      button.toolTip = "LunaAgent (compatibility mode)"
    }
    statusItem = item

    buildWindow()
    openWindow()
    timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
      self?.refreshStatus()
    }
  }

  private func installMenu() {
    let mainMenu = NSMenu()
    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    let appMenu = NSMenu(title: "LunaAgent")
    appMenu.addItem(withTitle: "Show LunaAgent", action: #selector(openWindow), keyEquivalent: "o")
    appMenu.addItem(NSMenuItem.separator())
    appMenu.addItem(withTitle: "Quit LunaAgent", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appMenuItem.submenu = appMenu
    NSApp.mainMenu = mainMenu
  }

  private func buildWindow() {
    let win = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    win.title = "LunaAgent"
    win.delegate = self
    win.isReleasedWhenClosed = false
    win.center()

    let root = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 560))
    var y = 560 - 16

    func addLabel(_ text: String, font: NSFont, frame: NSRect) -> NSTextField {
      let t = NSTextField(labelWithString: text)
      t.font = font
      t.frame = frame
      t.lineBreakMode = .byWordWrapping
      t.maximumNumberOfLines = 4
      root.addSubview(t)
      return t
    }

    bannerLabel = addLabel(
      MacOSCompat.modeBanner,
      font: .systemFont(ofSize: 11),
      frame: NSRect(x: 16, y: y - 40, width: 388, height: 40)
    )
    bannerLabel.textColor = .secondaryLabelColor
    y -= 52

    statusLabel = addLabel(
      "Status: …",
      font: .systemFont(ofSize: 12),
      frame: NSRect(x: 16, y: y - 48, width: 388, height: 48)
    )
    y -= 60

    let enrollTitle = addLabel("Enroll", font: .boldSystemFont(ofSize: 13), frame: NSRect(x: 16, y: y - 18, width: 200, height: 18))
    _ = enrollTitle
    y -= 26

    enrollURLField = NSTextField(frame: NSRect(x: 16, y: y - 24, width: 388, height: 24))
    enrollURLField.placeholderString = "Control URL (http://…)"
    root.addSubview(enrollURLField)
    y -= 32

    enrollCodeField = NSTextField(frame: NSRect(x: 16, y: y - 24, width: 260, height: 24))
    enrollCodeField.placeholderString = "Enroll code"
    root.addSubview(enrollCodeField)

    let enrollBtn = NSButton(frame: NSRect(x: 286, y: y - 26, width: 118, height: 28))
    enrollBtn.title = "Enroll"
    enrollBtn.bezelStyle = .rounded
    enrollBtn.target = self
    enrollBtn.action = #selector(doEnroll)
    root.addSubview(enrollBtn)
    y -= 40

    let vpnRow = NSStackView(frame: NSRect(x: 16, y: y - 28, width: 388, height: 28))
    vpnRow.orientation = .horizontal
    vpnRow.spacing = 8
    let up = NSButton(title: "Connect", target: self, action: #selector(doConnect))
    up.bezelStyle = .rounded
    let down = NSButton(title: "Disconnect", target: self, action: #selector(doDisconnect))
    down.bezelStyle = .rounded
    let refresh = NSButton(title: "Refresh", target: self, action: #selector(refreshStatus))
    refresh.bezelStyle = .rounded
    vpnRow.addArrangedSubview(up)
    vpnRow.addArrangedSubview(down)
    vpnRow.addArrangedSubview(refresh)
    root.addSubview(vpnRow)
    y -= 40

    let confTitle = addLabel("WireGuard config", font: .boldSystemFont(ofSize: 13), frame: NSRect(x: 16, y: y - 18, width: 200, height: 18))
    _ = confTitle
    y -= 24

    let scroll = NSScrollView(frame: NSRect(x: 16, y: 56, width: 388, height: y - 56))
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder
    confView = NSTextView(frame: scroll.contentView.bounds)
    confView.font = NSFont.userFixedPitchFont(ofSize: 11) ?? NSFont.systemFont(ofSize: 11)
    confView.isAutomaticQuoteSubstitutionEnabled = false
    confView.autoresizingMask = [.width, .height]
    scroll.documentView = confView
    root.addSubview(scroll)

    let loadBtn = NSButton(frame: NSRect(x: 16, y: 16, width: 120, height: 28))
    loadBtn.title = "Load conf"
    loadBtn.bezelStyle = .rounded
    loadBtn.target = self
    loadBtn.action = #selector(loadConf)
    root.addSubview(loadBtn)

    let saveBtn = NSButton(frame: NSRect(x: 144, y: 16, width: 160, height: 28))
    saveBtn.title = "Save & Connect"
    saveBtn.bezelStyle = .rounded
    saveBtn.target = self
    saveBtn.action = #selector(saveConf)
    root.addSubview(saveBtn)

    win.contentView = root
    window = win
  }

  @objc private func toggleWindow() {
    guard let window else { return }
    if window.isVisible {
      window.orderOut(nil)
    } else {
      openWindow()
    }
  }

  @objc private func openWindow() {
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    sender.orderOut(nil)
    return false
  }

  @objc private func refreshStatus() {
    let res = ipc.call(op: "status")
    let ok = (res["ok"] as? Bool) == true
    let data = res["data"] as? [String: Any] ?? [:]
    let enrolled = (data["enrolled"] as? Bool) ?? false
    let vpn = data["vpn"] as? [String: Any] ?? [:]
    let state = (vpn["state"] as? String) ?? (data["vpn_up"] as? Bool == true ? "up" : "down")
    let url = (data["control_url"] as? String) ?? ""
    let err = (res["error"] as? String) ?? (data["last_error"] as? String)
    let conn = data["connection"] as? [String: Any] ?? [:]
    let daemonVer = (conn["agent_version"] as? String) ?? (data["version"] as? String) ?? ""
    let ver = AppVersion.resolved(daemon: daemonVer)
    var lines = [
      "LunaAgent \(ver)",
      MacOSCompat.modeBanner,
      ok ? "Daemon: ok" : "Daemon: \(err ?? "not running")",
      "Enrolled: \(enrolled ? "yes" : "no")",
      "VPN: \(state)",
    ]
    if !url.isEmpty { lines.append("Panel: \(url)") }
    lines.append(MacOSCompat.loginItemNote)
    statusLabel.stringValue = lines.joined(separator: "\n")
    bannerLabel.stringValue = MacOSCompat.modeBanner

    let up = state == "up"
    statusItem?.button?.image = BrandAssets.menuBarImage(state: up ? .vpnOn : .idle)
    statusItem?.button?.image?.isTemplate = true
  }

  @objc private func doEnroll() {
    guard !busy else { return }
    let url = enrollURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let code = enrollCodeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !url.isEmpty, !code.isEmpty else {
      statusLabel.stringValue = "Enter Control URL and enroll code."
      return
    }
    busy = true
    DispatchQueue.global(qos: .userInitiated).async {
      let res = self.ipc.call(op: "enroll", args: ["control_url": url, "enroll_code": code])
      DispatchQueue.main.async {
        self.busy = false
        if (res["ok"] as? Bool) == true {
          self.statusLabel.stringValue = "Enrolled OK.\n" + MacOSCompat.modeBanner
        } else {
          self.statusLabel.stringValue = "Enroll failed: \(res["error"] as? String ?? "unknown")"
        }
        self.refreshStatus()
      }
    }
  }

  @objc private func doConnect() {
    guard !busy else { return }
    busy = true
    VPNNotifier.suppressUserInitiated()
    DispatchQueue.global(qos: .userInitiated).async {
      _ = self.ipc.call(op: "up")
      DispatchQueue.main.async {
        self.busy = false
        self.refreshStatus()
      }
    }
  }

  @objc private func doDisconnect() {
    guard !busy else { return }
    busy = true
    VPNNotifier.suppressUserInitiated()
    DispatchQueue.global(qos: .userInitiated).async {
      _ = self.ipc.call(op: "down")
      DispatchQueue.main.async {
        self.busy = false
        self.refreshStatus()
      }
    }
  }

  @objc private func loadConf() {
    let res = ipc.call(op: "get_wg_config")
    let data = res["data"] as? [String: Any] ?? res
    let conf = (data["conf_text"] as? String) ?? (data["conf"] as? String) ?? ""
    confView.string = conf
    if (res["ok"] as? Bool) != true, conf.isEmpty {
      statusLabel.stringValue = "Load conf: \(res["error"] as? String ?? "empty")"
    }
  }

  @objc private func saveConf() {
    let conf = confView.string
    guard !conf.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    busy = true
    DispatchQueue.global(qos: .userInitiated).async {
      let res = self.ipc.call(op: "apply_wg_config", args: ["conf_text": conf, "up": true])
      DispatchQueue.main.async {
        self.busy = false
        if (res["ok"] as? Bool) == true {
          self.statusLabel.stringValue = "Config saved & connect requested."
        } else {
          let err = res["error"] as? String ?? "failed"
          if err.lowercased().contains("admin") || err.lowercased().contains("unlock") {
            self.promptAdminThenRetry(conf: conf)
          } else {
            self.statusLabel.stringValue = "Save failed: \(err)"
          }
        }
        self.refreshStatus()
      }
    }
  }

  private func promptAdminThenRetry(conf: String) {
    let alert = NSAlert()
    alert.messageText = "Admin password"
    alert.informativeText = "Required to change WireGuard config."
    let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    alert.accessoryView = field
    alert.addButton(withTitle: "Unlock")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    let pw = field.stringValue
    DispatchQueue.global(qos: .userInitiated).async {
      _ = self.ipc.call(op: "admin_unlock", args: ["password": pw])
      let res = self.ipc.call(op: "apply_wg_config", args: ["conf_text": conf, "up": true])
      DispatchQueue.main.async {
        if (res["ok"] as? Bool) == true {
          self.statusLabel.stringValue = "Config saved & connect requested."
        } else {
          self.statusLabel.stringValue = "Save failed: \(res["error"] as? String ?? "failed")"
        }
        self.refreshStatus()
      }
    }
  }
}
