import AppKit
import SwiftUI

@available(macOS 13.0, *)
struct DeviceTabView: View {
  @ObservedObject var model: StatusViewModel

  var body: some View {
    Form {
      Section("Identity") {
        LabeledContent("Hostname", value: display(model.snapshot.hostname))
        LabeledContent("User", value: display(model.snapshot.username))
        copyRow("Device ID", model.snapshot.deviceID) { model.copyDeviceID() }
        copyRow("Serial", model.snapshot.serial) {
          copy(model.snapshot.serial)
        }
      }

      Section("System") {
        LabeledContent("Model", value: display(model.snapshot.model))
        LabeledContent("OS", value: display(model.snapshot.osVersion))
        LabeledContent("Agent version", value: model.snapshot.displayAgentVersion)
      }

      Section("macOS compatibility") {
        Text(MacOSCompat.modeBanner)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        ForEach(MacOSCompat.featureLines, id: \.self) { line in
          Text("• " + line)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Text(MacOSCompat.loginItemNote)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Section("Control") {
        LabeledContent("Enrolled", value: model.snapshot.enrolled ? "Yes" : "No")
        LabeledContent("Desired VPN", value: display(model.snapshot.desiredVPN.isEmpty ? "unchanged" : model.snapshot.desiredVPN))
        LabeledContent("VPN state", value: display(model.snapshot.vpnState))
        if !model.snapshot.controlURL.isEmpty {
          LabeledContent("Panel", value: model.snapshot.controlURL)
            .font(.caption)
        }
        if model.snapshot.enrolled {
          Button(role: .destructive) {
            if model.isAdminLocked {
              model.promptAdminUnlock("Admin password required to unenroll")
            } else {
              model.unenroll()
            }
          } label: {
            HStack {
              Text("Unenroll this Mac")
              if model.isAdminLocked { AdminLockGlyph() }
            }
          }
          .disabled(model.busy || !model.snapshot.daemonReachable)
        }
      }

      Section("Preferences") {
        Toggle("Alerts if VPN drops / restores", isOn: Binding(
          get: { model.vpnNotificationsEnabled },
          set: { model.setVPNNotifications($0) }
        ))
        Text("Launches at login automatically. No banners for Connect/Disconnect you press yourself — only unexpected drops and auto-reconnect. After Connect, the tunnel stays up until you Disconnect.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .padding(.bottom, 4)
  }

  private func display(_ s: String) -> String {
    s.isEmpty ? "—" : s
  }

  private func copy(_ s: String) {
    guard !s.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
  }

  @ViewBuilder
  private func copyRow(_ title: String, _ value: String, action: @escaping () -> Void) -> some View {
    HStack {
      LabeledContent(title, value: display(value))
      if !value.isEmpty {
        Button(action: action) {
          Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help("Copy \(title)")
      }
    }
  }
}
