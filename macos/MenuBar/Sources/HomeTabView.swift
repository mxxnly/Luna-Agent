import AppKit
import SwiftUI

@available(macOS 13.0, *)
struct HomeTabView: View {
  @ObservedObject var model: StatusViewModel
  var goEnroll: () -> Void
  var openWGConfig: () -> Void

  private var vpnUp: Bool {
    if let pending = model.pendingVPN { return pending }
    return model.snapshot.vpnState == "up"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      // Single hero: link status + VPN + primary action
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 10) {
          PulsingStatusIcon(
            systemName: statusSymbol,
            color: statusColor,
            active: model.snapshot.daemonReachable && (vpnUp || model.snapshot.enrolled)
          )
          .scaleEffect(0.85)

          VStack(alignment: .leading, spacing: 2) {
            Text(headline)
              .font(.headline)
            Text(subhead)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          Spacer(minLength: 0)
          if model.busy {
            ProgressView().controlSize(.small)
          }
        }

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
          .controlSize(.regular)
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
          .controlSize(.regular)
          .disabled(
            model.busy
              || !model.snapshot.daemonReachable
              || (!model.snapshot.hasWGConfig
                && model.wgConfText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          )
        }
      }
      .padding(10)
      .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

      HStack(spacing: 6) {
        MetricTileView(title: "CPU", systemImage: "cpu", percent: model.snapshot.cpuPct, tint: .blue)
        MetricTileView(title: "RAM", systemImage: "memorychip", percent: model.snapshot.ramPct, tint: .purple)
        MetricTileView(title: "Disk", systemImage: "internaldrive", percent: model.snapshot.diskPct, tint: .orange)
      }

      VStack(spacing: 6) {
        metaRow("Enrolled", model.snapshot.enrolled ? "Yes" : "No", model.snapshot.enrolled ? .green : .secondary)
        metaRow("Config", model.snapshot.hasWGConfig ? "Saved" : "None", .secondary)
        Toggle(isOn: Binding(
          get: { model.vpnNotificationsEnabled },
          set: { model.setVPNNotifications($0) }
        )) {
          Text("Alerts if VPN drops")
            .font(.caption)
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
      }
      .padding(.horizontal, 2)

      if let msg = model.actionMessage, !msg.isEmpty {
        Text(msg)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 0)

      Text("v\(model.snapshot.displayAgentVersion)")
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .trailing)

      VStack(spacing: 6) {
        if !model.snapshot.daemonReachable {
          Button {
            model.ensureDaemonThenRefresh()
          } label: {
            Label(model.startingDaemon ? "Starting…" : "Start Agent", systemImage: "play.fill")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .disabled(model.startingDaemon || model.busy)
        }

        HStack(spacing: 6) {
          if !model.snapshot.enrolled {
            Button("Enroll…", action: goEnroll)
              .buttonStyle(.bordered)
              .controlSize(.small)
              .disabled(model.busy)
          }
          Button {
            openWGConfig()
          } label: {
            HStack(spacing: 4) {
              Text("Config")
              if model.isAdminLocked { AdminLockGlyph() }
            }
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .disabled(model.busy || !model.snapshot.daemonReachable)

          if model.snapshot.enrolled {
            Button {
              model.copyDeviceID()
            } label: {
              Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Copy device ID")
            .disabled(model.busy)
          }
        }
      }
    }
    .padding(.horizontal, 14)
    .padding(.bottom, 12)
  }

  private var statusSymbol: String {
    if !model.snapshot.daemonReachable { return "xmark.octagon.fill" }
    if vpnUp { return "checkmark.shield.fill" }
    if model.snapshot.enrolled { return "link.circle.fill" }
    return "moon.stars.fill"
  }

  private var statusColor: Color {
    if !model.snapshot.daemonReachable { return .red }
    if vpnUp && !model.snapshot.handshakeOK { return .orange }
    if vpnUp { return .green }
    if model.snapshot.enrolled { return .accentColor }
    return .secondary
  }

  private var headline: String {
    if !model.snapshot.daemonReachable { return "Agent Offline" }
    if vpnUp && !model.snapshot.handshakeOK { return "VPN Up · No Handshake" }
    if vpnUp { return "VPN Connected" }
    if model.snapshot.enrolled { return "VPN Off" }
    return "Ready to Enroll"
  }

  private var subhead: String {
    if !model.snapshot.daemonReachable { return "Start the background agent." }
    if vpnUp && !model.snapshot.handshakeOK {
      return "Interface is up but peer unreachable — check WG config / Endpoint"
    }
    if vpnUp, let ip = model.snapshot.internalIP, !ip.isEmpty { return ip }
    if !model.snapshot.helperOK && model.snapshot.daemonReachable {
      return "WireGuard helper offline — Disconnect may ask for Mac password"
    }
    if model.snapshot.enrolled {
      return model.snapshot.hostname.isEmpty ? "Linked · config ready" : model.snapshot.hostname
    }
    return "Enroll with panel URL + code."
  }

  private func metaRow(_ title: String, _ value: String, _ color: Color) -> some View {
    HStack {
      Text(title).font(.caption).foregroundStyle(.secondary)
      Spacer()
      Text(value).font(.caption.weight(.medium)).foregroundStyle(color)
    }
  }
}
