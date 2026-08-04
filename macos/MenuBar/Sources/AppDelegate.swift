import AppKit
import SwiftUI

@available(macOS 13.0, *)
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private var statusItem: NSStatusItem?
  private var window: NSWindow?
  private var wgConfigWindow: NSWindow?
  private let viewModel = StatusViewModel()
  private let ipc = IPCClient()
  private var tooltipTimer: Timer?
  private let windowFrameKey = "lunaagent.window.frame"
  private var lastVPNUp: Bool?
  private var statusItemReady = false
  private var onboardingWindow: NSWindow?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSLog("LunaAgent full UI mode os=%@ — complete features (macOS 13+)", MacOSCompat.versionString)
    installMainMenu()
    VPNNotifier.requestPermissionIfNeeded()
    viewModel.refreshPrefs()
    // Always register background services (SMAppService) — no user toggle.
    _ = LoginItemSettings.ensureEnabled()
    DaemonManager.cleanupLegacyScatter()

    DispatchQueue.global(qos: .utility).async { [weak self] in
      _ = DaemonLauncher.ensureRunning()
      // Give watchdog/startup auto-connect a moment, then refresh menu bar.
      Thread.sleep(forTimeInterval: 0.8)
      DispatchQueue.main.async {
        self?.refreshStatusItem()
        NotificationCenter.default.post(name: .lunaAgentStatusDidChange, object: nil)
        self?.presentOnboardingIfNeeded()
      }
    }

    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = item.button {
      button.image = BrandAssets.menuBarImage(state: .idle)
      button.image?.isTemplate = true
      button.imagePosition = .imageOnly
      button.title = ""
      button.toolTip = "LunaAgent"
      button.target = self
      button.action = #selector(statusItemClicked(_:))
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
    statusItem = item
    statusItemReady = true

    tooltipTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
      self?.refreshStatusItem()
    }
    refreshStatusItem()

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onAgentStatusDidChange),
      name: .lunaAgentStatusDidChange,
      object: nil
    )
  }

  @objc private func onAgentStatusDidChange() {
    refreshStatusItem()
  }

  private func presentOnboardingIfNeeded() {
    let key = "luna.onboarding.permissions.done"
    if UserDefaults.standard.bool(forKey: key) { return }
    if onboardingWindow != nil { return }

    let view = PermissionsOnboardingView { [weak self] in
      self?.onboardingWindow?.close()
      self?.onboardingWindow = nil
      self?.openWindow()
    }
    let hosting = NSHostingController(rootView: view)
    let win = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 380, height: 360),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    win.title = "LunaAgent Setup"
    win.contentViewController = hosting
    win.isReleasedWhenClosed = false
    win.center()
    win.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    onboardingWindow = win
  }

  /// Accessory apps have no Edit menu by default — Cmd+C/V then do nothing.
  private func installMainMenu() {
    let main = NSMenu()

    let appMenuItem = NSMenuItem()
    main.addItem(appMenuItem)
    let appMenu = NSMenu(title: "LunaAgent")
    appMenu.addItem(withTitle: "About LunaAgent", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    appMenu.addItem(NSMenuItem.separator())
    appMenu.addItem(withTitle: "Hide LunaAgent", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    appMenu.addItem(withTitle: "Quit LunaAgent", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appMenuItem.submenu = appMenu

    let editItem = NSMenuItem()
    main.addItem(editItem)
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    edit.addItem(NSMenuItem.separator())
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = edit

    NSApp.mainMenu = main
  }

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent else {
      openWindow()
      return
    }
    if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
      showMenu(sender)
    } else {
      openWindow()
    }
  }

  private func showMenu(_ sender: NSStatusBarButton) {
    let menu = NSMenu()
    menu.addItem(NSMenuItem(title: "Open LunaAgent", action: #selector(openWindow), keyEquivalent: "o"))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(NSMenuItem(title: "Start agent", action: #selector(startDaemon), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "Connect VPN", action: #selector(vpnUp), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "Disconnect VPN", action: #selector(vpnDown), keyEquivalent: ""))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(NSMenuItem(title: "Copy Device ID", action: #selector(copyDeviceID), keyEquivalent: ""))
    menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    statusItem?.menu = menu
    statusItem?.button?.performClick(nil)
    statusItem?.menu = nil
  }

  @objc func openWindow() {
    if let window {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      viewModel.ensureDaemonThenRefresh()
      return
    }
    let root = StatusWindowView(model: viewModel, openWGConfig: { [weak self] in
      self?.openWGConfigWindow()
    })
    let hosting = NSHostingController(rootView: root)
    let contentSize = NSSize(width: 400, height: 550)
    let win = NSWindow(
      contentRect: NSRect(origin: .zero, size: contentSize),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    win.title = "LunaAgent"
    win.titleVisibility = .hidden
    win.titlebarAppearsTransparent = true
    win.isOpaque = false
    win.backgroundColor = .clear
    win.isMovableByWindowBackground = true
    win.contentViewController = hosting
    win.delegate = self
    win.setContentSize(contentSize)
    win.minSize = contentSize
    win.maxSize = contentSize
    // Prefer last position; always keep compact content size.
    win.setFrameAutosaveName("LunaAgentCompactWindow")
    if win.setFrameUsingName("LunaAgentCompactWindow") {
      var frame = win.frame
      frame.size = win.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
      win.setFrame(frame, display: false)
    } else if let saved = UserDefaults.standard.string(forKey: windowFrameKey) {
      var frame = NSRectFromString(saved)
      frame.size = win.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
      win.setFrame(frame, display: false)
    } else {
      win.center()
    }
    win.isReleasedWhenClosed = false
    win.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    window = win
  }

  @objc func openWGConfigWindow() {
    viewModel.loadSavedWGConfig { [weak self] in
      self?.presentWGConfigWindow()
    }
  }

  private func presentWGConfigWindow() {
    if let wgConfigWindow {
      wgConfigWindow.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    let editor = WGConfigEditorView(model: viewModel) { [weak self] in
      self?.wgConfigWindow?.close()
    }
    let hosting = NSHostingController(rootView: editor)
    let contentSize = NSSize(width: 520, height: 440)
    let win = NSWindow(
      contentRect: NSRect(origin: .zero, size: contentSize),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    win.title = "WireGuard Config"
    win.titleVisibility = .visible
    win.titlebarAppearsTransparent = false
    win.isOpaque = false
    win.backgroundColor = .clear
    win.contentViewController = hosting
    win.setContentSize(contentSize)
    win.minSize = NSSize(width: 420, height: 360)
    win.isReleasedWhenClosed = false
    win.delegate = self
    if let parent = window {
      let origin = NSPoint(
        x: parent.frame.midX - contentSize.width / 2,
        y: parent.frame.midY - contentSize.height / 2
      )
      win.setFrameOrigin(origin)
    } else {
      win.center()
    }
    win.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    wgConfigWindow = win
  }

  func windowDidResize(_ notification: Notification) {
    if (notification.object as? NSWindow) === window {
      persistWindowFrame()
    }
  }

  func windowDidMove(_ notification: Notification) {
    if (notification.object as? NSWindow) === window {
      persistWindowFrame()
    }
  }

  func windowWillClose(_ notification: Notification) {
    guard let closing = notification.object as? NSWindow else { return }
    if closing === window {
      persistWindowFrame()
    } else if closing === wgConfigWindow {
      wgConfigWindow = nil
    }
  }

  private func persistWindowFrame() {
    guard let window else { return }
    UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: windowFrameKey)
    window.saveFrame(usingName: "LunaAgentCompactWindow")
  }

  @objc func startDaemon() {
    DispatchQueue.global(qos: .userInitiated).async {
      _ = DaemonLauncher.ensureRunning()
      DispatchQueue.main.async { self.refreshStatusItem() }
    }
  }

  @objc func vpnUp() {
    VPNNotifier.suppressUserInitiated()
    DispatchQueue.global(qos: .userInitiated).async { [ipc] in
      _ = ipc.call(op: "vpn_up")
      DispatchQueue.main.async { self.refreshStatusItem() }
    }
  }

  @objc func vpnDown() {
    VPNNotifier.suppressUserInitiated()
    DispatchQueue.global(qos: .userInitiated).async { [ipc] in
      _ = ipc.call(op: "vpn_down")
      DispatchQueue.main.async { self.refreshStatusItem() }
    }
  }

  @objc func copyDeviceID() {
    DispatchQueue.global(qos: .utility).async { [ipc] in
      let res = ipc.call(op: "status", args: ["light": true])
      DispatchQueue.main.async {
        if let data = res["data"] as? [String: Any] {
          let id = (data["device_id"] as? String)
            ?? ((data["connection"] as? [String: Any])?["device_id"] as? String)
          if let id, !id.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(id, forType: .string)
          }
        }
      }
    }
  }

  private func refreshStatusItem() {
    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let self else { return }
      let res = self.ipc.call(op: "status", args: ["light": true])
      let snap = AgentStatusSnapshot.from(response: res)
      DispatchQueue.main.async {
        self.applyStatusItem(snap: snap)
      }
    }
  }

  private func applyStatusItem(snap: AgentStatusSnapshot) {
    guard let button = statusItem?.button else { return }
    let vpnUp = snap.daemonReachable && snap.vpnState == "up"
    let state: BrandAssets.MenuBarState
    if !snap.daemonReachable {
      state = .offline
    } else if vpnUp {
      state = .vpnOn
    } else {
      state = .idle
    }

    let img = BrandAssets.menuBarImage(state: state)
    button.image = img
    // Never force template on the green VPN badge — that made it nearly invisible.
    button.image?.isTemplate = (state != .vpnOn)
    button.contentTintColor = nil
    button.appearsDisabled = (state == .offline)

    if statusItemReady, let prev = lastVPNUp, prev != vpnUp {
      VPNNotifier.unexpectedChange(nowUp: vpnUp, ip: snap.internalIP)
    }
    if snap.daemonReachable {
      lastVPNUp = vpnUp
    }

    var parts: [String] = ["LunaAgent"]
    if !snap.daemonReachable {
      parts.append("offline")
    } else {
      parts.append(snap.enrolled ? "enrolled" : "not enrolled")
      parts.append(vpnUp ? "VPN on" : "VPN off")
      if vpnUp, let ip = snap.internalIP, !ip.isEmpty {
        parts.append(ip)
      }
    }
    button.toolTip = parts.joined(separator: " · ")
  }
}
