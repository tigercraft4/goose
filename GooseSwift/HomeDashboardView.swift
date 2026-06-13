import SwiftUI

struct HomeDashboardView: View {
  @Environment(GooseAppModel.self) private var model
  @EnvironmentObject private var router: AppRouter
  var healthStore: HealthDataStore
  @Binding var selectedDate: Date
  let openHealthRoute: (HealthRoute) -> Void
  @State private var showingScoreDatePicker = false
  @State private var showingCardioLoadSheet = false
  @State private var selectedHealthMonitorTrend: HealthMetricSnapshot?
  @State private var cachedLandingSnapshots: [HealthMetricSnapshot] = []
  @State private var cachedCardioLoadDays: [CardioLoadDay] = []
  @State private var cachedHealthMonitorSnapshots: [HealthMetricSnapshot] = []
  @State private var bpmRefreshTask: Task<Void, Never>?

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        HomeDailyScoreCard(
          scores: scoreSnapshots,
          actionSummary: dailyActionSummary,
          coachTip: CoachTipFactory.homeTip(healthStore: healthStore, appModel: model),
          openScore: openHealth,
          openCoach: openCoach
        )

        HomeStressEnergySection(
          stress: landingSnapshot(for: .stress),
          energy: landingSnapshot(for: .energyBank),
          openStress: { openHealth(.stress) }
        )

        HomeCardioLoadWidget(
          snapshot: landingSnapshot(for: .cardioLoad),
          days: cachedCardioLoadDays
        ) {
          showingCardioLoadSheet = true
          model.recordUIAction("health.sheet.opened", detail: "Cardio Load home widget")
        }

        HomeHealthMonitorSection(
          snapshots: cachedHealthMonitorSnapshots,
          openSnapshot: openHealthMonitorSnapshot
        )

        HomeTimelineSection(
          sleep: homeSnapshot(for: .sleep),
          activity: homeSnapshot(for: .strain),
          recovery: homeSnapshot(for: .recovery),
          activities: model.homeActivityTimelineItems,
          openSleep: { openHealth(.sleep) },
          openActivity: { openHealth(.strain) },
          openRecovery: { openHealth(.recovery) }
        )

        HomeDeviceStatusCard(
          ble: model.ble,
          onReconnect: { model.ble.reconnectRemembered() }
        )

        HomeToolsGrid(
          catalogReady: healthStore.catalogStatus.localizedCaseInsensitiveContains("loaded") && !healthStore.catalogStatus.localizedCaseInsensitiveContains("not loaded"),
          openSleepCoach: {
            router.openCoach(prompt: "Sleep coach: review my sleep quality and give me advice")
          },
          openActivity: { openHealth(.strain) },
          openCoach: { router.openCoach() },
          openCalibration: { router.openMore(.algorithms) }
        )

      }
      .padding(.horizontal, 16)
      .padding(.vertical, 18)
    }
    .scrollClipDisabled()
    .gooseScreenBackground()
    .navigationTitle("Today")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .overlay(alignment: .top) {
      HomeTopScrollFade()
        .allowsHitTesting(false)
    }
    .safeAreaInset(edge: .bottom, alignment: .trailing) {
      HomeStartActivityFloatingButton(session: model.activitySession)
        .padding(.trailing, 18)
        .padding(.bottom, 10)
    }
    .toolbar {
      ToolbarItem(placement: .principal) {
        ScoreDateTitleButton(
          title: homeTitle,
          subtitle: nil,
          action: { showingScoreDatePicker = true }
        )
      }
      ToolbarItem(placement: .topBarTrailing) {
        NavigationLink {
          DeviceView()
        } label: {
          Image(systemName: "applewatch")
            .font(.system(size: 17, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(deviceToolbarTint)
        }
        .accessibilityLabel("Device")
        .accessibilityValue(deviceToolbarAccessibilityValue)
      }
    }
    .onAppear {
      model.recordUIAction("page.opened", detail: "Home")
      refreshSnapshots()
    }
    .task {
      await healthStore.loadBridgeCatalogsIfNeeded()
      model.refreshActivityTimeline(for: selectedDate)
      refreshSnapshots()
    }
    .onChange(of: selectedDate) { _, newValue in
      model.refreshActivityTimeline(for: newValue)
      refreshSnapshots()
    }
    .onChange(of: model.ble.liveHeartRateBPM) { _, _ in
      bpmRefreshTask?.cancel()
      bpmRefreshTask = Task {
        try? await Task.sleep(for: .milliseconds(500))
        if !Task.isCancelled { refreshSnapshots() }
      }
    }
    .onChange(of: healthStore.catalogStatus) { _, _ in
      refreshSnapshots()
    }
    .sheet(isPresented: $showingScoreDatePicker) {
      ScoreDatePickerSheet(
        title: "Daily Scores",
        routes: [.sleep, .recovery, .strain],
        snapshots: scorePickerSnapshots,
        selectedDate: $selectedDate
      )
    }
    .sheet(isPresented: $showingCardioLoadSheet) {
      CardioLoadSheet(store: healthStore)
    }
    .sheet(item: $selectedHealthMonitorTrend) { snapshot in
      SleepV2BevelTrendSheet(snapshot: snapshot)
    }
  }

  private var scoreSnapshots: [HealthMetricSnapshot] {
    [
      datedHomeSnapshot(for: .sleep),
      datedHomeSnapshot(for: .recovery),
      datedHomeSnapshot(for: .strain),
    ]
  }

  private var scorePickerSnapshots: [HealthMetricSnapshot] {
    [
      homeSnapshot(for: .sleep),
      homeSnapshot(for: .recovery),
      homeSnapshot(for: .strain),
    ]
  }

  private var homeTitle: String {
    ScoreDateTimeline.dateLabel(for: selectedDate)
  }

  private var deviceToolbarTint: Color {
    deviceToolbarConnected ? .green : .red
  }

  private var deviceToolbarAccessibilityValue: String {
    deviceToolbarConnected ? "Connected" : "Disconnected"
  }

  private var deviceToolbarConnected: Bool {
    let state = model.ble.connectionState.lowercased()
    return state == "ready" || state == "connected"
  }

  private var dailyActionSummary: String {
    let inputAction = healthStore.metricInputReadinessNextActionSummary()
    if !inputAction.isEmpty {
      return inputAction
    }
    return healthStore.packetDerivedScoreNextActionSummary()
  }

  private func refreshSnapshots() {
    cachedLandingSnapshots = healthStore.landingSnapshots(
      liveHeartRateBPM: model.ble.liveHeartRateBPM,
      liveHeartRateSource: model.ble.liveHeartRateSource,
      liveHeartRateUpdatedAt: model.ble.liveHeartRateUpdatedAt,
      stableDailyMetrics: true
    )
    cachedCardioLoadDays = healthStore.cardioLoadWeeklyPoints()
    cachedHealthMonitorSnapshots = healthStore.healthMonitorSnapshots(allowLiveFallbacks: false)
  }

  private func landingSnapshot(for route: HealthRoute) -> HealthMetricSnapshot {
    cachedLandingSnapshots.first { $0.route == route } ?? healthStore.snapshot(for: route)
  }

  private func homeSnapshot(for route: HealthRoute) -> HealthMetricSnapshot {
    let snapshot = landingSnapshot(for: route)
    guard route == .strain, snapshot.unit != "%" else {
      return snapshot
    }
    let rawValue = firstNumber(in: snapshot.displayValue) ?? firstNumber(in: snapshot.value) ?? 0
    let percent = min(max(Int((rawValue / 21 * 100).rounded()), 0), 100)
    return HealthMetricSnapshot(
      id: snapshot.id,
      route: snapshot.route,
      group: snapshot.group,
      title: snapshot.title,
      value: "\(percent)",
      unit: "%",
      status: snapshot.status,
      freshness: snapshot.freshness,
      provenance: snapshot.provenance,
      source: snapshot.source,
      systemImage: snapshot.systemImage,
      tint: snapshot.tint,
      trend: snapshot.trend
    )
  }

  private func datedHomeSnapshot(for route: HealthRoute) -> HealthMetricSnapshot {
    ScoreDateTimeline.datedSnapshot(from: homeSnapshot(for: route), date: selectedDate)
  }

  private func openHealth(_ route: HealthRoute) {
    openHealthRoute(route)
    model.recordUIAction("health.deep_link.opened", detail: route.title)
  }

  private func openHealthMonitorSnapshot(_ snapshot: HealthMetricSnapshot) {
    if snapshot.id == "resting-hr" {
      selectedHealthMonitorTrend = snapshot
    } else {
      openHealth(.healthMonitor)
    }
  }

  private func openCoach(_ prompt: String) {
    router.openCoach(prompt: prompt)
    model.recordUIAction("coach.opened", detail: "Home daily score card")
  }
}

// MARK: - HOME-01: Device Status Card

private struct HomeDeviceStatusCard: View {
  let ble: GooseBLEClient
  let onReconnect: () -> Void

  private var isConnected: Bool {
    let s = ble.connectionState.lowercased()
    return s == "ready" || s == "connected" || s == "discovering"
  }

  private var stateColor: Color { isConnected ? .green : .red }

  private var lastSyncText: String {
    guard let date = ble.lastSyncAt else { return "Never" }
    let rel = RelativeDateTimeFormatter()
    rel.unitsStyle = .short
    return rel.localizedString(for: date, relativeTo: Date()).capitalized
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Circle()
          .fill(stateColor)
          .frame(width: 8, height: 8)
        Text(ble.activeDeviceName)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
        Spacer()
        Text(ble.connectionState.localizedConnectionState)
          .font(.caption.weight(.medium))
          .foregroundStyle(stateColor)
      }

      HStack(spacing: 20) {
        HomeDeviceStat(
          label: "Battery",
          value: ble.batteryLevelPercent.map { "\($0)%" } ?? "--"
        )
        HomeDeviceStat(
          label: "HR",
          value: ble.liveHeartRateBPM.map { "\($0) bpm" } ?? "--"
        )
        HomeDeviceStat(label: "Last Sync", value: lastSyncText)
        Spacer()
        if !isConnected && ble.hasRememberedDevice {
          Button(action: onReconnect) {
            Text("Reconnect")
              .font(.caption.weight(.semibold))
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .background(.blue.opacity(0.15), in: Capsule())
              .foregroundStyle(.blue)
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding(14)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}

private struct HomeDeviceStat: View {
  let label: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
      Text(value)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(.primary)
    }
  }
}

// MARK: - HOME-02: Tools Grid

private struct HomeToolsGrid: View {
  let catalogReady: Bool
  let openSleepCoach: () -> Void
  let openActivity: () -> Void
  let openCoach: () -> Void
  let openCalibration: () -> Void

  private let columns = [GridItem(.flexible()), GridItem(.flexible())]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("TOOLS")
        .font(.system(size: 11, weight: .black))
        .foregroundStyle(.secondary)

      LazyVGrid(columns: columns, spacing: 10) {
        HomeToolButton(
          title: "Sleep Coach",
          systemImage: "moon.zzz",
          ready: catalogReady,
          action: openSleepCoach
        )
        HomeToolButton(
          title: "Activity",
          systemImage: "figure.run",
          ready: catalogReady,
          action: openActivity
        )
        HomeToolButton(
          title: "Journal",
          systemImage: "book.pages",
          ready: true,
          action: openCoach
        )
        HomeToolButton(
          title: "Calibration",
          systemImage: "slider.horizontal.3",
          ready: catalogReady,
          action: openCalibration
        )
      }
    }
  }
}

private struct HomeToolButton: View {
  let title: String
  let systemImage: String
  let ready: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: systemImage)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(ready ? .primary : .tertiary)
        VStack(alignment: .leading, spacing: 1) {
          Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
          Text(ready ? "Ready" : "Loading")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(ready ? .green : .secondary)
        }
        Spacer()
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

// HOME-03 (evidence footer) moved to More → Developer → Debug as the
// "Data Provenance" section — see MoreDebugViews.swift.

