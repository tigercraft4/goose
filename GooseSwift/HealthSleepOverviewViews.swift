import Darwin
import Foundation
import SwiftUI
import UIKit

struct SleepV2OverviewPage: View {
  @EnvironmentObject private var router: AppRouter
  var store: HealthDataStore
  var ble: GooseBLEClient
  @Binding var selectedDate: Date
  @Environment(\.colorScheme) private var colorScheme
  @State private var showingInsightsSheet = false
  @State private var showingAlarmSheet = false
	  @State private var showingSleepNeededSheet = false
	  @State private var showingDatePicker = false
    @State private var selectedTrend: HealthMetricSnapshot?
	  @State private var selectedPrimarySleep: PrimarySleepDetail?
	  @State private var scrollOffsetY: CGFloat = 0
    @State private var autoBandSyncRequested = false
	  private let heroHeight: CGFloat = 320
	  private let heroBackgroundHeight: CGFloat = 560
    private var autoBandSleepSyncEnabled: Bool {
      let processInfo = ProcessInfo.processInfo
      return processInfo.arguments.contains("--goose-auto-band-sleep-sync")
        || processInfo.environment["GOOSE_AUTO_BAND_SLEEP_SYNC"] == "1"
    }

	  var body: some View {
	    let palette = SleepV2Palette(colorScheme: colorScheme)
		    ScrollViewReader { _ in
	      ZStack(alignment: .top) {
	        palette.background
	          .ignoresSafeArea()

	        SleepV2ScenicBackground(palette: palette)
	          .frame(height: heroBackgroundHeight)
	          .offset(y: min(scrollOffsetY, 0))
	          .ignoresSafeArea(edges: .top)
	          .allowsHitTesting(false)

	        ScrollView {
	          LazyVStack(alignment: .leading, spacing: 0) {
	            SleepV2ScrollOffsetProbe()

	            SleepV2Hero(
	              palette: palette,
	              title: "Sleep",
	              dateLabel: dateLabel,
	              score: sleepScore,
	              onDateTap: { showingDatePicker = true }
	            )
	            .frame(height: heroHeight)

	            VStack(alignment: .leading, spacing: 14) {
	              HStack(spacing: 12) {
                SleepV2StatCard(
                  palette: palette,
                  systemImage: "bed.double.fill",
                  label: "Time in Bed",
                  value: primarySleep?.timeInBedText ?? "No data"
                )
                SleepV2StatCard(
                  palette: palette,
                  systemImage: "clock.fill",
                  label: "Time Asleep",
                  value: primarySleep?.durationText ?? "No data"
                )
              }
              .frame(height: 96)

              SleepV2CoachingCard(palette: palette, tip: coachTip) {
                router.openCoach(prompt: coachTip.prompt)
              }

	              SleepV2ActionRow(
	                palette: palette,
	                systemImage: "sparkles",
	                title: "View insights",
	                action: { showingInsightsSheet = true }
	              )

	              SleepV2SleepWindowCard(
                palette: palette,
                onWakeTap: { showingAlarmSheet = true },
                onSleepNeeded: { showingSleepNeededSheet = true }
              )

              SleepV2BandSyncCard(store: store, ble: ble, palette: palette) {
                startBandSleepSync(automatic: false)
              }

              SleepStagingCard(palette: palette, result: store.sleepStagingResult)

              SleepV2SectionHeader(title: "Timeline", palette: palette)

              SleepV2TimelineRow(
                palette: palette,
                session: primarySleep,
                action: {
                  if let primarySleep {
                    selectedPrimarySleep = primarySleep
                  }
                }
              )

              SleepV2SectionHeader(title: "Trends", palette: palette)

              VStack(spacing: 14) {
                ForEach(store.trendRows(for: .sleep)) { snapshot in
                  SleepV2TrendRow(palette: palette, snapshot: snapshot) {
                    selectedTrend = snapshot
                  }
	                }
	              }
	            }
	            .padding(.horizontal, 18)
	            .padding(.bottom, 34)
	          }
	        }
	        .coordinateSpace(name: SleepV2ScrollOffsetProbe.coordinateSpaceName)
	        .onPreferenceChange(SleepV2ScrollOffsetPreferenceKey.self) { value in
	          scrollOffsetY = value
	        }
	      }
	    }
    .navigationTitle("Sleep")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .principal) {
        Text("Sleep")
          .font(.headline.weight(.semibold))
          .foregroundStyle(palette.text)
      }
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          showingAlarmSheet = true
        } label: {
          Image(systemName: "alarm")
        }
        .accessibilityLabel("Sleep alarm settings")
      }
    }
    .onAppear {
      Task { await store.loadBridgeCatalogsIfNeeded() }
      startBandSleepSyncIfReady()
      Task { await store.runSleepStaging() }
    }
    .onChange(of: ble.canSyncHistorical) { _, _ in
      startBandSleepSyncIfReady()
    }
    .onChange(of: ble.historicalSyncStatus) { _, newValue in
      if newValue == "synced" {
        Task { await store.refreshSleepAfterBandSync(packetCount: ble.historicalPacketCount) }
      } else if newValue == "failed" {
        store.markBandSleepSyncFailed(ble.historicalSyncStatus)
      }
    }
    .sheet(isPresented: $showingDatePicker) {
      ScoreDatePickerSheet(
        title: "Sleep",
        routes: [.sleep],
        snapshots: [store.snapshot(for: .sleep)],
        selectedDate: $selectedDate
      )
    }
	    .sheet(isPresented: $showingAlarmSheet) {
	      SleepV2AlarmSheet(ble: ble)
	    }
	    .sheet(isPresented: $showingSleepNeededSheet) {
	      SleepV2SleepNeededSheet(palette: palette)
	    }
	    .sheet(isPresented: $showingInsightsSheet) {
	      SleepV2InsightsSheet(palette: palette)
	    }
		    .sheet(item: $selectedTrend) { snapshot in
		      SleepV2BevelTrendSheet(snapshot: snapshot)
		    }
    .sheet(item: $selectedPrimarySleep) { sleep in
      PrimarySleepDetailSheet(sleep: sleep)
    }
  }

  private var selectedSnapshot: HealthMetricSnapshot {
    ScoreDateTimeline.datedSnapshot(
      from: store.snapshot(for: .sleep),
      date: selectedDate
    )
  }

  private var primarySleep: PrimarySleepDetail? {
    store.primarySleep()
  }

  private var sleepScore: Int {
    SleepV2Numbers.firstInt(in: selectedSnapshot.value)
      ?? SleepV2Numbers.firstInt(in: primarySleep?.scoreText ?? "")
      ?? 92
  }

  private var dateLabel: String {
    let suffix = selectedDate.formatted(.dateTime.day().month(.abbreviated))
    let prefix = ScoreDateTimeline.dateLabel(for: selectedDate)
    return "\(prefix), \(suffix)"
  }

  private var coachTip: CoachInlineTip {
    CoachTipFactory.sleepTip(healthStore: store, ble: ble)
  }

  private func startBandSleepSyncIfReady() {
    guard autoBandSleepSyncEnabled else {
      if !autoBandSyncRequested {
        autoBandSyncRequested = true
        ble.record(
          source: "health.sleep",
          title: "band_sleep_sync.auto_skipped",
          body: "autoBandSleepSync=false"
        )
      }
      return
    }
    guard !autoBandSyncRequested, ble.canSyncHistorical else {
      return
    }
    autoBandSyncRequested = true
    startBandSleepSync(automatic: true)
  }

  private func startBandSleepSync(automatic: Bool) {
    store.markBandSleepSyncRequested(
      automatic: automatic,
      canSync: ble.canSyncHistorical,
      detail: ble.historicalSyncStatus
    )
    guard ble.canSyncHistorical else {
      return
    }
    ble.syncHistoricalPackets(rangeFirst: true)
  }

}

// MARK: - SleepStagingCard

struct SleepStagingCard: View {
  let palette: SleepV2Palette
  let result: SleepStagingResult?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 8) {
        Image(systemName: "moon.stars.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(palette.accent)
        Text("Sleep Stages")
          .font(.headline.weight(.semibold))
          .foregroundStyle(palette.text)
        Spacer()
        if let r = result, !r.stagingMethod.contains("unknown") {
          Text(r.stagingMethodLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.mutedText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.thinMaterial, in: Capsule())
        }
      }

      if let r = result, !r.sortedStages.isEmpty {
        SleepFourClassHypnogramBar(stages: r.sortedStages, palette: palette)
          .frame(height: 22)

        LazyVGrid(
          columns: [GridItem(.flexible()), GridItem(.flexible())],
          spacing: 10
        ) {
          ForEach(r.sortedStages, id: \.stage) { item in
            SleepStagePill(
              palette: palette,
              stage: item.stage,
              minutes: item.minutes
            )
          }
        }

        Divider()
          .background(palette.separator.opacity(0.60))

        HStack(spacing: 0) {
          SleepStagingMetricCell(palette: palette, label: String(localized: "Efficiency"), value: r.sleepEfficiencyText)
          Divider().frame(maxHeight: 36).background(palette.separator.opacity(0.54))
          SleepStagingMetricCell(palette: palette, label: String(localized: "Sleep onset"), value: r.solText)
          Divider().frame(maxHeight: 36).background(palette.separator.opacity(0.54))
          SleepStagingMetricCell(palette: palette, label: String(localized: "Awake after onset"), value: r.wasoText)
        }

        if !r.respAvailable {
          HStack(spacing: 6) {
            Image(systemName: "info.circle")
              .font(.caption.weight(.semibold))
            Text("REM inferred without respiratory data")
              .font(.caption.weight(.medium))
          }
          .foregroundStyle(palette.mutedText)
          .padding(.top, 2)
        }
      } else {
        HStack(spacing: 8) {
          Image(systemName: "moon.zzz")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(palette.mutedText)
          Text("No staging data — no accelerometer or sleep data")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(palette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
      }
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(palette.surface)
        .shadow(color: palette.shadow.opacity(0.30), radius: 8, x: 0, y: 3)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .stroke(palette.separator.opacity(0.60), lineWidth: 1)
    )
  }
}

struct SleepFourClassHypnogramBar: View {
  let stages: [(stage: String, minutes: Double)]
  let palette: SleepV2Palette

  var body: some View {
    GeometryReader { proxy in
      let total = max(stages.map(\.minutes).reduce(0, +), 1)
      HStack(spacing: 3) {
        ForEach(stages, id: \.stage) { item in
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(stageColor(item.stage))
            .frame(width: max(proxy.size.width * CGFloat(item.minutes / total) - 3, 10))
        }
      }
    }
  }

  private func stageColor(_ stage: String) -> Color {
    switch stage.lowercased() {
    case "wake":  return Color(red: 0.72, green: 0.72, blue: 0.72)  // gray
    case "light": return Color(red: 0.38, green: 0.62, blue: 0.88)  // light blue
    case "deep":  return Color(red: 0.16, green: 0.36, blue: 0.78)  // dark blue
    case "rem":   return Color(red: 0.62, green: 0.30, blue: 0.84)  // purple
    default:      return palette.accent
    }
  }
}

struct SleepStagePill: View {
  let palette: SleepV2Palette
  let stage: String
  let minutes: Double

  var body: some View {
    HStack(spacing: 8) {
      RoundedRectangle(cornerRadius: 3, style: .continuous)
        .fill(stageColor)
        .frame(width: 12, height: 12)
      VStack(alignment: .leading, spacing: 2) {
        Text(stageLabel)
          .font(.caption.weight(.semibold))
          .foregroundStyle(palette.text)
        Text(HealthDataStore.minutesText(minutes))
          .font(.caption2.weight(.medium))
          .foregroundStyle(palette.secondaryText)
      }
      Spacer(minLength: 0)
    }
  }

  private var stageLabel: String {
    switch stage.lowercased() {
    case "wake":  return "Acordado"
    case "light": return "Sono leve"
    case "deep":  return "Sono profundo"
    case "rem":   return "REM"
    default:      return stage.capitalized
    }
  }

  private var stageColor: Color {
    switch stage.lowercased() {
    case "wake":  return Color(red: 0.72, green: 0.72, blue: 0.72)
    case "light": return Color(red: 0.38, green: 0.62, blue: 0.88)
    case "deep":  return Color(red: 0.16, green: 0.36, blue: 0.78)
    case "rem":   return Color(red: 0.62, green: 0.30, blue: 0.84)
    default:      return .secondary
    }
  }
}

struct SleepStagingMetricCell: View {
  let palette: SleepV2Palette
  let label: String
  let value: String

  var body: some View {
    VStack(spacing: 4) {
      Text(value)
        .font(.subheadline.weight(.semibold))
        .fontDesign(.rounded)
        .foregroundStyle(palette.text)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
      Text(label)
        .font(.caption2.weight(.medium))
        .foregroundStyle(palette.mutedText)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 4)
  }
}

