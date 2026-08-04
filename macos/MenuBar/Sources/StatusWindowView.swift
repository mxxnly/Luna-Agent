import SwiftUI

// MARK: - Tabs

@available(macOS 13.0, *)
enum LunaTab: String, CaseIterable, Identifiable, Hashable {
  case home, vpn, enroll, device, metrics

  var id: String { rawValue }

  var title: String {
    switch self {
    case .home: return "Home"
    case .vpn: return "VPN"
    case .enroll: return "Enroll"
    case .device: return "Device"
    case .metrics: return "Metrics"
    }
  }

  var systemImage: String {
    switch self {
    case .home: return "house.fill"
    case .vpn: return "network"
    case .enroll: return "qrcode.viewfinder"
    case .device: return "laptopcomputer"
    case .metrics: return "chart.bar.fill"
    }
  }
}

// MARK: - Root

@available(macOS 13.0, *)
struct StatusWindowView: View {
  @ObservedObject var model: StatusViewModel
  var openWGConfig: () -> Void = {}
  @State private var tab: LunaTab = .home

  var body: some View {
    VStack(spacing: 0) {
      header
        .padding(.horizontal, 14)
        .padding(.top, 26)
        .padding(.bottom, 6)

      Picker("Section", selection: $tab) {
        ForEach(LunaTab.allCases) { item in
          Image(systemName: item.systemImage)
            .tag(item)
            .help(item.title)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .padding(.horizontal, 14)
      .padding(.bottom, 6)

      if model.snapshot.adminConfigured {
        AdminLockStatusBar(model: model)
          .padding(.horizontal, 14)
          .padding(.bottom, 6)
      }

      Group {
        switch tab {
        case .home:
          HomeTabView(
            model: model,
            goEnroll: { withAnimation(.easeInOut) { tab = .enroll } },
            openWGConfig: {
              if model.isAdminLocked {
                model.promptAdminUnlock("Admin password required to edit config")
              } else {
                openWGConfig()
              }
            }
          )
        case .vpn:
          VPNTabView(model: model, openWGConfig: {
            if model.isAdminLocked {
              model.promptAdminUnlock("Admin password required to edit config")
            } else {
              openWGConfig()
            }
          })
        case .enroll:
          EnrollTabView(model: model)
        case .device:
          DeviceTabView(model: model)
        case .metrics:
          MetricsTabView(model: model)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .animation(.easeInOut(duration: 0.2), value: tab)
    }
    .frame(width: 400, height: 550)
    .background(.regularMaterial)
    .sheet(isPresented: $model.showAdminUnlock) {
      AdminUnlockSheet(model: model)
    }
    .onAppear {
      model.startPolling()
      tab = model.snapshot.enrolled ? .home : .enroll
      model.wantMetrics = (tab == .home || tab == .metrics)
    }
    .onDisappear { model.stopPolling() }
    .onChange(of: model.snapshot.enrolled) { enrolled in
      if enrolled && tab == .enroll {
        withAnimation(.easeInOut) { tab = .home }
      }
    }
    .onChange(of: tab) { newTab in
      model.wantMetrics = (newTab == .home || newTab == .metrics)
      if model.wantMetrics {
        model.refreshAsync(light: false)
      }
    }
  }

  private var header: some View {
    HStack(spacing: 10) {
      Image(nsImage: BrandAssets.appIconImage())
        .resizable()
        .interpolation(.high)
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

      VStack(alignment: .leading, spacing: 1) {
        Text("LunaAgent")
          .font(.headline)
        Text(headerSubtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Text("v\(model.snapshot.displayAgentVersion)")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.tertiary)
      }

      Spacer(minLength: 0)

      if model.busy || model.startingDaemon {
        ProgressView()
          .controlSize(.small)
      }
    }
  }

  private var headerSubtitle: String {
    if !model.snapshot.daemonReachable { return "Agent offline" }
    if model.snapshot.vpnState == "up" { return "VPN connected" }
    if model.snapshot.enrolled { return "Linked to panel" }
    return "Ready to enroll"
  }
}
