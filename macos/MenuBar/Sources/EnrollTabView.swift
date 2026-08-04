import SwiftUI

@available(macOS 13.0, *)
struct EnrollTabView: View {
  @ObservedObject var model: StatusViewModel
  @FocusState private var focused: Field?

  private enum Field {
    case url, code
  }

  var body: some View {
    VStack(spacing: 12) {
      VStack(spacing: 4) {
        Image(systemName: "qrcode.viewfinder")
          .font(.system(size: 26, weight: .medium))
          .foregroundStyle(Color.accentColor)
        Text("Enroll Device")
          .font(.headline)
        Text("Panel URL + one-time code.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
      .padding(.top, 4)

      VStack(alignment: .leading, spacing: 10) {
        field(label: "Control URL", focus: .url) {
          TextField("http://…", text: $model.enrollURL)
            .textFieldStyle(.roundedBorder)
            .focused($focused, equals: .url)
          Button { model.pasteEnrollURL() } label: {
            Image(systemName: "doc.on.clipboard")
          }
          .buttonStyle(.borderless)
          .help("Paste URL")
        }

        field(label: "One-time code", focus: .code) {
          SecureField("Code from panel", text: $model.enrollCode)
            .textFieldStyle(.roundedBorder)
            .focused($focused, equals: .code)
          Button { model.pasteEnrollCode() } label: {
            Image(systemName: "doc.on.clipboard")
          }
          .buttonStyle(.borderless)
          .help("Paste code")
        }
      }

      if let msg = model.enrollMessage {
        Text(msg)
          .font(.caption2)
          .foregroundStyle(model.enrollOK == true ? .green : .red)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
      }

      Spacer(minLength: 0)

      Button {
        if model.isAdminLocked {
          model.promptAdminUnlock("Admin password required to enroll")
        } else {
          model.enroll()
        }
      } label: {
        HStack(spacing: 6) {
          if model.busy && model.busyLabel.contains("Enroll") {
            ProgressView().controlSize(.small)
          }
          Text(model.busy && model.busyLabel.contains("Enroll") ? "Enrolling…" : "Enroll Device")
          if model.isAdminLocked { AdminLockGlyph() }
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .disabled(
        model.busy
          || model.enrollURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || model.enrollCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      )
    }
    .padding(.horizontal, 14)
    .padding(.bottom, 12)
  }

  private func field<Content: View>(
    label: String,
    focus: Field,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
      HStack(spacing: 6) { content() }
    }
  }
}
