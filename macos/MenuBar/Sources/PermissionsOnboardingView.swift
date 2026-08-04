import SwiftUI

/// First-run setup: register SMAppService background services + notifications (macOS 13+).
@available(macOS 13.0, *)
struct PermissionsOnboardingView: View {
  var onDone: () -> Void
  @State private var busy = false
  @State private var message = ""
  @State private var snap = DaemonManager.snapshot()

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Finish setup (Beta)")
        .font(.title2.weight(.semibold))
      Text("LunaAgent needs background services for VPN and the menu bar, plus optional alerts if the tunnel drops unexpectedly.")
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: 10) {
        row(icon: "bolt.horizontal.circle.fill", title: "Launch at login",
            detail: DaemonManager.statusLabel(snap.loginItem))
        row(icon: "gearshape.2.fill", title: "Background agent",
            detail: DaemonManager.statusLabel(snap.agent))
        row(icon: "lock.shield.fill", title: "WireGuard helper",
            detail: DaemonManager.statusLabel(snap.helper))
        row(icon: "bell.badge.fill", title: "Notifications",
            detail: "Allow alerts for unexpected VPN drops")
      }
      .padding(12)
      .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

      if !message.isEmpty {
        Text(message)
          .font(.caption)
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
      }

      Button {
        runSetup()
      } label: {
        HStack {
          if busy { ProgressView().controlSize(.small) }
          Text(busy ? "Working…" : "Enable background services")
            .frame(maxWidth: .infinity)
        }
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .disabled(busy)

      if snap.needsApproval {
        Button("Open System Settings…") {
          DaemonManager.openLoginItemsSettings()
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
      }

      Button("Continue") { finish() }
        .buttonStyle(.borderless)
        .frame(maxWidth: .infinity)
    }
    .padding(20)
    .frame(width: 400)
    .background(.regularMaterial)
    .onAppear {
      DaemonManager.cleanupLegacyScatter()
      refresh()
    }
  }

  private func row(icon: String, title: String, detail: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: icon)
        .foregroundStyle(.secondary)
        .frame(width: 22)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.subheadline.weight(.semibold))
        Text(detail).font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private func runSetup() {
    busy = true
    message = ""
    DispatchQueue.global(qos: .userInitiated).async {
      VPNNotifier.requestPermissionIfNeeded()
      let err = DaemonManager.registerAll()
      let ipc = IPCClient()
      _ = DaemonManager.ensureRunning(ipcPing: { ipc.ping() })
      DispatchQueue.main.async {
        busy = false
        refresh()
        if let err {
          message = err
        } else if snap.needsApproval {
          message = "Approve LunaAgent under Login Items & Extensions, then tap Continue."
          DaemonManager.openLoginItemsSettings()
        } else {
          finish()
        }
      }
    }
  }

  private func refresh() {
    snap = DaemonManager.snapshot()
  }

  private func finish() {
    UserDefaults.standard.set(true, forKey: "luna.onboarding.permissions.done")
    onDone()
  }
}
