import SwiftUI

@available(macOS 13.0, *)
struct MetricsTabView: View {
  @ObservedObject var model: StatusViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        MetricGaugeView(
          title: "CPU",
          percent: model.snapshot.cpuPct,
          tint: .blue
        )
        MetricGaugeView(
          title: "RAM",
          percent: model.snapshot.ramPct,
          detail: ByteFormat.pair(used: model.snapshot.ramUsed, total: model.snapshot.ramTotal),
          tint: .purple
        )
        MetricGaugeView(
          title: "Disk",
          percent: model.snapshot.diskPct,
          detail: ByteFormat.pair(used: model.snapshot.diskUsed, total: model.snapshot.diskTotal),
          tint: .orange
        )
      }
      .padding(.horizontal, 4)

      HStack {
        Text("Top Processes")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
        Spacer()
        Text("CPU · RAM")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 14)

      if model.snapshot.topCPU.isEmpty {
        ContentUnavailableHint(
          title: "No process samples",
          systemImage: "chart.bar.doc.horizontal",
          note: model.snapshot.daemonReachable
            ? "Waiting for the next metrics poll…"
            : "Start the agent to collect metrics."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 14)
      } else {
        List(model.snapshot.topCPU.prefix(12)) { proc in
          ProcessRowView(process: proc)
            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
      }
    }
    .padding(.top, 4)
    .padding(.bottom, 8)
  }
}

@available(macOS 13.0, *)
private struct ContentUnavailableHint: View {
  let title: String
  let systemImage: String
  let note: String

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: systemImage)
        .font(.largeTitle)
        .foregroundStyle(.secondary)
      Text(title)
        .font(.callout.weight(.medium))
      Text(note)
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding()
  }
}
