import SwiftUI

@available(macOS 13.0, *)
struct AdminUnlockSheet: View {
  @ObservedObject var model: StatusViewModel
  @FocusState private var passwordFocused: Bool

  private var reason: String {
    let msg = (model.adminUnlockMessage ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if msg.isEmpty || msg.contains("Unlocked") || msg == "Wrong password" || msg == "Enter admin password" {
      return "Disconnect, config, and re-enroll need the organization password."
    }
    return msg
  }

  private var errorText: String? {
    guard let msg = model.adminUnlockMessage else { return nil }
    if msg.contains("Wrong") || msg == "Enter admin password" || msg.contains("failed") {
      return msg
    }
    return nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        Image(systemName: "lock.shield.fill")
          .font(.title2)
          .foregroundStyle(.orange)
        VStack(alignment: .leading, spacing: 2) {
          Text("Unlock admin")
            .font(.headline)
          Text(reason)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      SecureField("Organization admin password", text: $model.adminPassword)
        .textFieldStyle(.roundedBorder)
        .focused($passwordFocused)
        .onSubmit { model.adminUnlock() }

      Text("Not the Mac login · open for 10 minutes")
        .font(.caption2)
        .foregroundStyle(.tertiary)

      if let err = errorText {
        Text(err)
          .font(.caption)
          .foregroundStyle(.red)
      }

      HStack {
        Button("Cancel") {
          model.showAdminUnlock = false
          model.adminPassword = ""
          model.adminUnlockMessage = nil
        }
        .keyboardShortcut(.cancelAction)
        Spacer()
        Button {
          model.adminUnlock()
        } label: {
          if model.busy && model.busyLabel.contains("Unlock") {
            ProgressView().controlSize(.small)
          } else {
            Text("Unlock")
          }
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(model.busy || model.adminPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(16)
    .frame(width: 320)
    .onAppear {
      passwordFocused = true
      if model.adminUnlockMessage?.contains("Unlocked") == true {
        model.adminUnlockMessage = nil
      }
    }
  }
}
