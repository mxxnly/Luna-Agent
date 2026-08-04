import SwiftUI

/// Separate window content for pasting / saving WireGuard config.
@available(macOS 13.0, *)
struct WGConfigEditorView: View {
  @ObservedObject var model: StatusViewModel
  var onClose: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("WireGuard Config")
            .font(.headline)
          Text(model.snapshot.hasWGConfig || !model.wgConfText.isEmpty
            ? "Edit the saved .conf, then save or connect."
            : "Paste a full .conf, then save or connect.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if model.isAdminLocked { AdminLockGlyph() }
        Button {
          model.pasteWGConfig()
        } label: {
          Label("Paste", systemImage: "doc.on.clipboard")
        }
        .buttonStyle(.bordered)
        .disabled(model.busy || model.isAdminLocked)
      }

      if model.isAdminLocked {
        HStack(spacing: 8) {
          Text("Locked — unlock to edit.")
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer(minLength: 0)
          Button("Unlock") {
            model.promptAdminUnlock("Admin password required to edit config")
          }
          .buttonStyle(.bordered)
          .tint(.orange)
          .controlSize(.small)
        }
      }

      TextEditor(text: $model.wgConfText)
        .font(.system(.body, design: .monospaced))
        .scrollContentBackground(.hidden)
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(.quaternary, lineWidth: 1)
        )
        .disabled(model.busy || model.isAdminLocked)
        .opacity(model.isAdminLocked ? 0.55 : 1)

      if let msg = model.wgMessage {
        Text(msg)
          .font(.caption)
          .foregroundStyle(model.wgOK == false ? .red : .secondary)
          .lineLimit(2)
      } else {
        Text("Needs [Interface], PrivateKey, and [Peer].")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }

      HStack(spacing: 8) {
        Button("Close") { onClose?() }
          .keyboardShortcut(.cancelAction)

        Spacer()

        Button("Save only") {
          model.applyWGConfig(connect: false)
        }
        .buttonStyle(.bordered)
        .disabled(model.busy || confEmpty || model.isAdminLocked)

        Button {
          model.applyWGConfig(connect: true)
        } label: {
          HStack(spacing: 6) {
            if model.busy && model.busyLabel.contains("connecting") {
              ProgressView().controlSize(.small)
            }
            Text("Save & Connect")
            if model.isAdminLocked { AdminLockGlyph() }
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.busy || !model.snapshot.daemonReachable || confEmpty || model.isAdminLocked)
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(16)
    .frame(width: 520, height: 440)
    .background(.regularMaterial)
    .sheet(isPresented: $model.showAdminUnlock) {
      AdminUnlockSheet(model: model)
    }
  }

  private var confEmpty: Bool {
    model.wgConfText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}
