import SwiftUI

@available(macOS 13.0, *)
struct VPNTabView: View {
  @ObservedObject var model: StatusViewModel
  var openWGConfig: () -> Void

  private var vpnUp: Bool {
    if let pending = model.pendingVPN { return pending }
    return model.snapshot.vpnState == "up"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Image(systemName: vpnUp ? "lock.shield.fill" : "lock.open.fill")
          .font(.title2)
          .foregroundStyle(vpnUp ? .green : .red)
        VStack(alignment: .leading, spacing: 2) {
          Text(vpnUp ? "Connected" : "Disconnected")
            .font(.headline)
          Text(detailLine)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
        if model.busy { ProgressView().controlSize(.small) }
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

      VStack(spacing: 6) {
        row("Config", model.snapshot.hasWGConfig ? "Saved" : "Not set")
        if !model.snapshot.desiredVPN.isEmpty {
          row("Desired", model.snapshot.desiredVPN)
        }
        row("Mode", model.snapshot.tunnelMode == "dry-run" ? "dry-run" : "live")
      }

      if let msg = model.wgMessage, model.wgOK == false {
        Text(msg)
          .font(.caption2)
          .foregroundStyle(.red)
          .lineLimit(2)
      }

      Spacer(minLength: 0)

      VStack(spacing: 6) {
        if vpnUp {
          Button(role: .destructive) {
            if model.isAdminLocked {
              model.promptAdminUnlock("Admin password required to disconnect")
            } else {
              model.vpnDown()
            }
          } label: {
            HStack(spacing: 6) {
              Label("Disconnect", systemImage: "xmark.circle")
              if model.isAdminLocked { AdminLockGlyph() }
            }
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .disabled(model.busy || !model.snapshot.daemonReachable)
        } else {
          Button {
            model.vpnUp()
          } label: {
            Label("Connect", systemImage: "bolt.horizontal.circle.fill")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .tint(.green)
          .disabled(model.busy || !model.snapshot.daemonReachable || !model.snapshot.hasWGConfig)
        }

        Button {
          openWGConfig()
        } label: {
          HStack(spacing: 6) {
            Text(model.snapshot.hasWGConfig ? "Edit Config…" : "Add Config…")
            if model.isAdminLocked { AdminLockGlyph() }
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(model.busy || !model.snapshot.daemonReachable)
      }
    }
    .padding(.horizontal, 14)
    .padding(.bottom, 12)
  }

  private var detailLine: String {
    if vpnUp, let ip = model.snapshot.internalIP, !ip.isEmpty { return ip }
    return model.snapshot.tunnelMode == "dry-run" ? "Simulated tunnel" : "Live WireGuard"
  }

  private func row(_ title: String, _ value: String) -> some View {
    HStack {
      Text(title).font(.caption).foregroundStyle(.secondary)
      Spacer()
      Text(value).font(.caption.weight(.medium))
    }
  }
}
