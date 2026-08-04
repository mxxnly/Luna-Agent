import AppKit
import SwiftUI

// MARK: - Admin lock chrome

enum AdminLockCopy {
  static func remainingLabel(_ seconds: Int) -> String {
    let s = max(0, seconds)
    let m = s / 60
    let r = s % 60
    if m <= 0 { return "\(r)s" }
    if r == 0 { return "\(m)m" }
    return "\(m):\(String(format: "%02d", r))"
  }
}

/// Tiny lock glyph for protected controls (no text).
@available(macOS 13.0, *)
struct AdminLockGlyph: View {
  var body: some View {
    Image(systemName: "lock.fill")
      .font(.system(size: 10, weight: .bold))
      .foregroundStyle(.orange)
      .help("Requires admin unlock")
  }
}

/// One-line lock strip — keeps chrome out of the tab content.
@available(macOS 13.0, *)
struct AdminLockStatusBar: View {
  @ObservedObject var model: StatusViewModel

  private var locked: Bool { model.isAdminLocked }

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: locked ? "lock.fill" : "lock.open.fill")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(locked ? Color.orange : Color.green)
        .frame(width: 14)

      Text(locked ? "Admin locked" : "Unlocked \(AdminLockCopy.remainingLabel(model.snapshot.adminUnlockedRemaining))")
        .font(.caption2.weight(.medium))
        .foregroundStyle(locked ? Color.orange : Color.secondary)
        .lineLimit(1)

      Spacer(minLength: 0)

      if locked {
        Button("Unlock") {
          model.adminUnlockMessage = nil
          model.adminPassword = ""
          model.showAdminUnlock = true
        }
        .buttonStyle(.bordered)
        .tint(.orange)
        .controlSize(.mini)
      } else {
        Button("Lock") { model.adminLockNow() }
          .buttonStyle(.borderless)
          .controlSize(.mini)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(
      (locked ? Color.orange.opacity(0.12) : Color.primary.opacity(0.05)),
      in: RoundedRectangle(cornerRadius: 7, style: .continuous)
    )
    .animation(.easeInOut(duration: 0.18), value: locked)
  }
}

@available(macOS 13.0, *)
struct MetricTileView: View {
  let title: String
  let systemImage: String
  let percent: Double
  var tint: Color = .accentColor

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 3) {
        Image(systemName: systemImage)
          .font(.caption2)
          .foregroundStyle(tint)
        Text(title)
          .font(.caption2)
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
        Text("\(Int(percent.rounded()))%")
          .font(.caption2.weight(.semibold).monospacedDigit())
      }
      ProgressView(value: min(max(percent, 0), 100), total: 100)
        .tint(barColor)
        .controlSize(.mini)
      }
    .padding(8)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var barColor: Color {
    if percent >= 85 { return .red }
    if percent >= 65 { return .orange }
    return tint
  }
}

// MARK: - Circular gauge (Metrics)

@available(macOS 13.0, *)
struct MetricGaugeView: View {
  let title: String
  let percent: Double
  var detail: String? = nil
  var tint: Color = .accentColor

  var body: some View {
    VStack(spacing: 6) {
      ZStack {
        Circle()
          .stroke(.quaternary, lineWidth: 7)
        Circle()
          .trim(from: 0, to: CGFloat(min(max(percent, 0), 100) / 100))
          .stroke(gaugeColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .animation(.easeInOut(duration: 0.35), value: percent)
        Text("\(Int(percent.rounded()))%")
          .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
      }
      .frame(width: 64, height: 64)

      Text(title)
        .font(.caption.weight(.medium))
      if let detail, !detail.isEmpty {
        Text(detail)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
    }
    .frame(maxWidth: .infinity)
  }

  private var gaugeColor: Color {
    if percent >= 85 { return .red }
    if percent >= 65 { return .orange }
    return tint
  }
}

// MARK: - Pulsing status icon

@available(macOS 13.0, *)
struct PulsingStatusIcon: View {
  let systemName: String
  let color: Color
  var active: Bool = true

  @State private var pulse = false

  var body: some View {
    Image(systemName: systemName)
      .font(.system(size: 28, weight: .semibold))
      .foregroundStyle(color)
      .symbolRenderingMode(.hierarchical)
      .scaleEffect(active && pulse ? 1.08 : 1.0)
      .opacity(active && pulse ? 1.0 : 0.85)
      .shadow(color: active ? color.opacity(0.45) : .clear, radius: active && pulse ? 10 : 0)
      .onAppear {
        guard active else { return }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
          pulse = true
        }
      }
      .onChange(of: active) { isActive in
        pulse = false
        if isActive {
          withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            pulse = true
          }
        }
      }
  }
}

// MARK: - Process row

@available(macOS 13.0, *)
struct ProcessRowView: View {
  let process: ProcessRow

  var body: some View {
    HStack(spacing: 8) {
      Text(process.name.isEmpty ? "—" : process.name)
        .font(.caption)
        .lineLimit(1)
      Spacer(minLength: 4)
      Text(String(format: "%.0f%%", process.cpuPct))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: 36, alignment: .trailing)
      Text(ByteFormat.string(process.ramBytes))
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.tertiary)
        .frame(width: 52, alignment: .trailing)
    }
    .padding(.vertical, 2)
  }
}

// MARK: - Helpers

enum ByteFormat {
  static func string(_ n: Int64) -> String {
    guard n > 0 else { return "—" }
    let units = ["B", "KB", "MB", "GB", "TB"]
    var v = Double(n)
    var i = 0
    while v >= 1024, i < units.count - 1 {
      v /= 1024
      i += 1
    }
    return String(format: i == 0 ? "%.0f %@" : "%.1f %@", v, units[i])
  }

  static func pair(used: Int64, total: Int64) -> String {
    "\(string(used)) / \(string(total))"
  }
}

@available(macOS 13.0, *)
struct CopyableValueRow: View {
  let title: String
  let value: String
  var copyLabel: String = "Copy"

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(value.isEmpty ? "—" : value)
          .font(.body.monospaced())
          .textSelection(.enabled)
          .lineLimit(2)
      }
      Spacer(minLength: 8)
      if !value.isEmpty {
        Button {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(value, forType: .string)
        } label: {
          Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help(copyLabel)
      }
    }
  }
}
