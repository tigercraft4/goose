import SwiftUI

// MARK: - Coach Route Navigation Links (COACH-09 to COACH-12)

struct CoachRoutesSection: View {
  var healthStore: HealthDataStore

  private let routes: [(String, String, AnyView)] = []

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("COACH ROUTES")
        .font(.system(size: 11, weight: .black))
        .foregroundStyle(.secondary)

      NavigationLink {
        CoachSleepRouteView(healthStore: healthStore)
      } label: {
        CoachRouteRow(title: "Sleep Coach", subtitle: "Wind-down, bedtime, debt", systemImage: "moon.zzz", tint: .indigo)
      }
      .buttonStyle(.plain)

      NavigationLink {
        CoachRecoveryRouteView(healthStore: healthStore)
      } label: {
        CoachRouteRow(title: "Recovery Insights", subtitle: "HRV, RHR, resp rate, skin temp", systemImage: "heart.fill", tint: .green)
      }
      .buttonStyle(.plain)

      NavigationLink {
        CoachStrainRouteView(healthStore: healthStore)
      } label: {
        CoachRouteRow(title: "Strain Guidance", subtitle: "Score, target, exercise, HR", systemImage: "figure.run", tint: .orange)
      }
      .buttonStyle(.plain)

      NavigationLink {
        CoachStressRouteView(healthStore: healthStore)
      } label: {
        CoachRouteRow(title: "Stress Guidance", subtitle: "Score, HRV, zones, non-activity", systemImage: "brain.head.profile", tint: .purple)
      }
      .buttonStyle(.plain)
    }
  }
}

private struct CoachRouteRow: View {
  let title: String
  let subtitle: String
  let systemImage: String
  let tint: Color

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 36, height: 36)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()
      Image(systemName: "chevron.right")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tertiary)
    }
    .padding(12)
    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

// MARK: - COACH-09: Sleep Coach Route

struct CoachSleepRouteView: View {
  var healthStore: HealthDataStore
  @Environment(GooseAppModel.self) private var model
  @State private var alarmTime: Date = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()

  private var sleep: PrimarySleepDetail? { healthStore.primarySleepDetail }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        CoachRouteHeader(
          systemImage: "moon.zzz",
          title: "Sleep Coach",
          subtitle: sleep == nil
            ? String(localized: "No sleep data for today")
            : String(localized: "Last night's analysis"),
          tint: .indigo
        )

        CoachInfoGroup(title: String(localized: "SCHEDULE")) {
          CoachInfoRow(label: "Wind-down", value: windDownTime)
          CoachInfoRow(label: String(localized: "Bedtime"), value: sleep?.startLabel ?? "—")
          CoachInfoRow(label: String(localized: "Wake"), value: sleep?.endLabel ?? "—")
          CoachInfoRow(label: String(localized: "Duration"), value: sleep?.durationText ?? "—")
        }

        CoachInfoGroup(title: String(localized: "QUALITY")) {
          CoachInfoRow(label: "Score", value: sleep?.scoreText ?? "—")
          CoachInfoRow(label: String(localized: "Quality"), value: sleep?.qualityText ?? "—")
          CoachInfoRow(label: String(localized: "Time in bed"), value: sleep?.timeInBedText ?? "—")
          CoachInfoRow(label: "WASO", value: sleep?.wasoText ?? "—")
        }

        if let sleep {
          CoachInfoGroup(title: String(localized: "SLEEP DEBT")) {
            CoachInfoRow(label: String(localized: "Goal"), value: HealthDataStore.minutesText(Self.sleepGoalMinutes))
            CoachInfoRow(label: String(localized: "Actual"), value: sleep.durationText)
            CoachInfoRow(label: String(localized: "Debt"), value: sleepDebt(actualMinutes: sleep.durationMinutes))
          }
        }

        wakeAlarmSection
      }
      .padding(16)
    }
    .gooseScreenBackground()
    .navigationTitle("Sleep Coach")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var windDownTime: String {
    guard let start = sleep?.startLabel, start != "--" else { return "—" }
    // Parse HH:mm and subtract 30 min
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.dateFormat = "HH:mm"
    guard let date = fmt.date(from: start) else {
      // start did not parse as a valid HH:mm time; avoid surfacing a malformed
      // value (e.g. "25:99") to the user and fall back to a neutral placeholder.
      return "—"
    }
    let adjusted = date.addingTimeInterval(-30 * 60)
    return fmt.string(from: adjusted)
  }

  // Single source of truth for the nightly sleep goal, used for both the displayed
  // "Goal" row and the debt computation so they can never drift apart.
  private static let sleepGoalMinutes = 8.0 * 60

  private func sleepDebt(actualMinutes: Double) -> String {
    let debt = Self.sleepGoalMinutes - actualMinutes
    return debt <= 0 ? String(localized: "None") : HealthDataStore.minutesText(debt)
  }

  private var isDisconnected: Bool { model.ble.connectionState != "ready" }

  @ViewBuilder
  private var wakeAlarmSection: some View {
    CoachInfoGroup(title: "ALARME DE DESPERTAR") {
      VStack(spacing: 12) {
        DatePicker(
          "Hora de acordar",
          selection: $alarmTime,
          displayedComponents: .hourAndMinute
        )
        .labelsHidden()
        .disabled(isDisconnected || model.alarmIsArmed)
        .opacity(isDisconnected || model.alarmIsArmed ? 0.4 : 1)
        .accessibilityHint(isDisconnected ? "Conecta o WHOOP para ativar" : "")

        if isDisconnected && !model.alarmIsArmed {
          HStack(spacing: 8) {
            Image(systemName: "sensor.tag.radiowaves.forward")
              .foregroundStyle(.secondary)
            Text("Conecta o WHOOP para usar o alarme")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)
        }

        Button {
          if model.alarmIsArmed {
            model.ble.disableWhoopAlarms()
            model.alarmIsArmed = false
            model.scheduledAlarmTime = nil
          } else {
            guard model.ble.connectionState == "ready",
                  model.ble.pendingAlarmCommand == nil else { return }
            model.ble.setWhoopAlarm(at: alarmTime)
            model.ble.buzz(loops: 2)
            model.alarmIsArmed = true
            model.scheduledAlarmTime = alarmTime
          }
        } label: {
          Text(model.alarmIsArmed ? "Cancelar Alarme" : "Armar Alarme")
            .font(.body.weight(.semibold))
            .foregroundStyle(model.alarmIsArmed ? Color.red : Color.indigo)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
              (model.alarmIsArmed ? Color.red : Color.indigo).opacity(0.14),
              in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .disabled(isDisconnected)
        .accessibilityLabel(model.alarmIsArmed ? "Cancelar alarme armado" : "Armar alarme de despertar")
      }
    }
  }
}

// MARK: - COACH-10: Recovery Insights Route

struct CoachRecoveryRouteView: View {
  var healthStore: HealthDataStore

  private var r: RecoveryV1Result? { healthStore.recoveryV1Result }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        CoachRouteHeader(
          systemImage: "heart.fill",
          title: "Recovery Insights",
          subtitle: r == nil
            ? String(localized: "Score not yet calculated")
            : String(localized: "Based on last night's data"),
          tint: .green
        )

        CoachInfoGroup(title: "SCORE") {
          CoachInfoRow(label: "Recovery", value: r?.score.map { "\($0)" } ?? "—", accent: r?.bandColor)
          CoachInfoRow(label: String(localized: "Level"), value: r.map { colorBandLabel($0.colourBand) } ?? "—")
          CoachInfoRow(label: String(localized: "Confidence"), value: r?.trustLevel ?? "—")
          CoachInfoRow(label: "z-HRV", value: r?.zHRV.map { String(format: "%.2f", $0) } ?? "—")
          CoachInfoRow(label: "z-RHR", value: r?.zRHR.map { String(format: "%.2f", $0) } ?? "—")
        }

        CoachInfoGroup(title: String(localized: "BIOMETRICS")) {
          CoachInfoRow(label: "HRV (SDNN)", value: healthStore.hkHRVSDNNMs.map { String(format: "%.0f ms", $0) } ?? "—")
          CoachInfoRow(label: "RHR", value: healthStore.hkRestingHR.map { String(format: "%.0f bpm", $0) } ?? "—")
          CoachInfoRow(label: "Resp. Rate", value: healthStore.hkRespiratoryRate.map { String(format: "%.1f rpm", $0) } ?? "—")
          CoachInfoRow(label: String(localized: "Skin temp Δ"), value: healthStore.hkSkinTempDeltaC.map { String(format: "%+.2f °C", $0) } ?? "—")
        }

        if let r {
          CoachInfoGroup(title: String(localized: "RECOMMENDATION")) {
            Text(recommendation(for: r.colourBand))
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      .padding(16)
    }
    .gooseScreenBackground()
    .navigationTitle("Recovery Insights")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func colorBandLabel(_ band: String) -> String {
    switch band {
    case "verde": return String(localized: "Ready")
    case "amarelo": return String(localized: "Moderate")
    case "vermelho": return String(localized: "Fatigued")
    default: return band.capitalized
    }
  }

  private func recommendation(for band: String) -> String {
    switch band {
    case "verde": return String(localized: "High recovery — good day for intense training or new load.")
    case "amarelo": return String(localized: "Moderate recovery — light or technique training. Avoid a new peak effort.")
    case "vermelho": return String(localized: "Low recovery — prioritise rest, sleep and hydration today.")
    default: return String(localized: "Waiting for enough data for a personalised recommendation.")
    }
  }
}

// MARK: - COACH-11: Strain Guidance Route

struct CoachStrainRouteView: View {
  var healthStore: HealthDataStore

  private var strainSnapshot: HealthMetricSnapshot { healthStore.snapshot(for: .strain) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        CoachRouteHeader(
          systemImage: "figure.run",
          title: "Strain Guidance",
          subtitle: String(localized: "Today's training load"),
          tint: .orange
        )

        CoachInfoGroup(title: String(localized: "LOAD")) {
          CoachInfoRow(label: "Strain Score", value: strainSnapshot.displayValue.isEmpty ? "—" : strainSnapshot.displayValue)
          CoachInfoRow(label: String(localized: "Target"), value: String(localized: "10 (moderate)"))
          CoachInfoRow(label: String(localized: "Status"), value: strainSnapshot.status)
          CoachInfoRow(label: String(localized: "Source"), value: strainSnapshot.source.label)
        }

        let sessions = healthStore.exerciseSessions
        CoachInfoGroup(title: String(localized: "ACTIVITIES (\(sessions.count))")) {
          if sessions.isEmpty {
            CoachInfoRow(label: String(localized: "Activities"), value: String(localized: "None detected"))
          } else {
            ForEach(sessions.prefix(3)) { session in
              CoachInfoRow(
                label: Self.formatTime(session.startTs),
                value: String(format: "%.0f min · strain %.1f", session.durationSeconds / 60, session.strain)
              )
            }
            CoachInfoRow(label: String(localized: "Total"), value: Self.totalDuration(sessions))
          }
        }

        CoachInfoGroup(title: String(localized: "GUIDANCE")) {
          Text(strainGuidance)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(16)
    }
    .gooseScreenBackground()
    .navigationTitle("Strain Guidance")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var strainGuidance: String {
    let raw = Double(strainSnapshot.displayValue.filter("0123456789.".contains)) ?? 0
    if raw == 0 { return String(localized: "No strain data for today. Do a session to start tracking.") }
    if raw < 7 { return String(localized: "Low load — you can raise tomorrow's training intensity.") }
    if raw < 14 { return String(localized: "Moderate load — on target. Keep this rhythm.") }
    return String(localized: "High load — prioritise active recovery or rest tomorrow.")
  }

  private static func formatTime(_ ts: Double) -> String {
    let date = Date(timeIntervalSince1970: ts)
    let fmt = DateFormatter()
    fmt.timeStyle = .short
    return fmt.string(from: date)
  }

  private static func totalDuration(_ sessions: [ExerciseSessionDisplayItem]) -> String {
    let total = sessions.reduce(0) { $0 + $1.durationSeconds }
    let mins = Int(total / 60)
    return "\(mins) min"
  }
}

// MARK: - COACH-12: Stress Guidance Route

struct CoachStressRouteView: View {
  var healthStore: HealthDataStore

  private var stress: StressAlgorithmSummary {
    healthStore.stressAlgorithmSummary()
  }
  private var stressSnapshot: HealthMetricSnapshot { healthStore.snapshot(for: .stress) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        CoachRouteHeader(
          systemImage: "brain.head.profile",
          title: "Stress Guidance",
          subtitle: stress.hasData ? String(localized: "Based on today's data") : stress.status,
          tint: .purple
        )

        CoachInfoGroup(title: "SCORE") {
          CoachInfoRow(label: "Stress", value: stress.score.map { String(format: "%.0f", $0) } ?? (stressSnapshot.displayValue.isEmpty ? "—" : stressSnapshot.displayValue))
          CoachInfoRow(label: String(localized: "Average HR"), value: stress.averageHeartRate.map { String(format: "%.0f bpm", $0) } ?? "—")
          CoachInfoRow(label: String(localized: "Latest HRV"), value: healthStore.hkHRVSDNNMs.map { String(format: "%.0f ms", $0) } ?? "—")
          CoachInfoRow(label: "Freshness", value: stress.freshness)
        }

        CoachInfoGroup(title: String(localized: "ZONES")) {
          CoachInfoRow(label: String(localized: "High (>60)"), value: String(format: "%.0f min", stress.high.durationMinutes))
          CoachInfoRow(label: String(localized: "Medium (30–60)"), value: String(format: "%.0f min", stress.medium.durationMinutes))
          CoachInfoRow(label: String(localized: "Low (<30)"), value: String(format: "%.0f min", stress.low.durationMinutes))
          CoachInfoRow(label: String(localized: "Samples"), value: "\(stress.sampleCount)")
        }

        CoachInfoGroup(title: "NON-ACTIVITY STRESS") {
          Text(stress.hasData
            ? String(localized: "Stress is calculated across all periods, including exercise windows.")
            : stress.status)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(16)
    }
    .gooseScreenBackground()
    .navigationTitle("Stress Guidance")
    .navigationBarTitleDisplayMode(.inline)
  }
}

// MARK: - Shared Components

struct CoachRouteHeader: View {
  let systemImage: String
  let title: String
  let subtitle: String
  let tint: Color

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: systemImage)
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 52, height: 52)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.title2.weight(.bold))
        Text(subtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.bottom, 4)
  }
}

struct CoachInfoGroup<Content: View>: View {
  let title: String
  let content: Content

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(.system(size: 11, weight: .black))
        .foregroundStyle(.secondary)
        .padding(.bottom, 8)

      VStack(spacing: 0) {
        content
      }
      .padding(12)
      .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
  }
}

struct CoachInfoRow: View {
  let label: String
  let value: String
  var accent: Color?

  var body: some View {
    HStack {
      Text(label)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Spacer()
      Text(value)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(accent ?? .primary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .padding(.vertical, 6)
    .overlay(alignment: .bottom) {
      Divider().opacity(0.5)
    }
  }
}
