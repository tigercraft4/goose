import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

@main
struct GooseWorkoutLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    GooseWorkoutLiveActivityWidget()
  }
}

struct GooseWorkoutLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: WorkoutLiveActivityAttributes.self) { context in
      WorkoutLiveActivityLockScreenView(context: context)
        .activityBackgroundTint(WorkoutLiveActivityStyle.background)
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          WorkoutLiveActivityIcon(attributes: context.attributes)
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(spacing: 2) {
            Text(context.attributes.activityName)
              .font(.system(.headline, design: .rounded))
              .lineLimit(1)
            Text(context.state.status)
              .font(.system(.caption, design: .rounded).weight(.semibold))
              .foregroundStyle(WorkoutLiveActivityStyle.secondaryText)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          WorkoutLiveActivityElapsedText(state: context.state)
            .font(.system(.headline, design: .rounded).monospacedDigit())
            .foregroundStyle(WorkoutLiveActivityStyle.workoutYellow)
        }
        DynamicIslandExpandedRegion(.bottom) {
          WorkoutLiveActivityMetricRow(attributes: context.attributes, state: context.state)
        }
      } compactLeading: {
        Image(systemName: context.attributes.activitySystemImage)
          .foregroundStyle(WorkoutLiveActivityStyle.exerciseGreen)
      } compactTrailing: {
        WorkoutLiveActivityElapsedText(state: context.state)
          .font(.system(.caption2, design: .rounded).monospacedDigit())
          .foregroundStyle(WorkoutLiveActivityStyle.workoutYellow)
      } minimal: {
        Image(systemName: context.attributes.activitySystemImage)
          .foregroundStyle(WorkoutLiveActivityStyle.exerciseGreen)
      }
    }
  }
}

private struct WorkoutLiveActivityLockScreenView: View {
  let context: ActivityViewContext<WorkoutLiveActivityAttributes>

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 14) {
        WorkoutLiveActivityIcon(attributes: context.attributes)

        VStack(alignment: .leading, spacing: 4) {
          Text(context.attributes.activityName)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
          Text("\(context.state.status) · \(context.attributes.environmentName)")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(WorkoutLiveActivityStyle.secondaryText)
            .lineLimit(1)
        }

        Spacer(minLength: 10)

        WorkoutLiveActivityElapsedText(state: context.state)
          .font(.system(size: 30, weight: .regular, design: .rounded).monospacedDigit())
          .foregroundStyle(WorkoutLiveActivityStyle.workoutYellow)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
      }

      HStack(alignment: .center, spacing: 12) {
        WorkoutLiveActivityMetricRow(attributes: context.attributes, state: context.state)
        Spacer(minLength: 0)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
  }
}

private struct WorkoutLiveActivityIcon: View {
  let attributes: WorkoutLiveActivityAttributes

  var body: some View {
    Image(systemName: attributes.activitySystemImage)
      .font(.system(size: 22, weight: .semibold, design: .rounded))
      .foregroundStyle(WorkoutLiveActivityStyle.exerciseGreen)
      .frame(width: 46, height: 46)
      .background(WorkoutLiveActivityStyle.exerciseGreen.opacity(0.24), in: Circle())
  }
}

private struct WorkoutLiveActivityMetricRow: View {
  let attributes: WorkoutLiveActivityAttributes
  let state: WorkoutLiveActivityAttributes.ContentState

  var body: some View {
    HStack(spacing: 18) {
      metric(value: heartRateText, label: "HR", color: WorkoutLiveActivityStyle.heartRed)
      metric(value: "\(state.activeCalories)", label: "KCAL", color: WorkoutLiveActivityStyle.movePink)
      if attributes.usesGPS {
        metric(value: distanceText, label: "DIST", color: WorkoutLiveActivityStyle.standCyan)
      } else if let averageHeartRate = state.averageHeartRate {
        metric(value: "\(averageHeartRate)", label: "AVG", color: WorkoutLiveActivityStyle.standCyan)
      }
    }
  }

  private var heartRateText: String {
    state.currentHeartRate.map(String.init) ?? "--"
  }

  private var distanceText: String {
    guard let distanceMeters = state.distanceMeters else {
      return "--"
    }
    if state.usesImperialUnits {
      return String(format: "%.2f mi", max(distanceMeters, 0) / 1609.344)
    }
    if distanceMeters >= 1000 {
      return String(format: "%.2f km", distanceMeters / 1000)
    }
    return "\(Int(max(distanceMeters, 0).rounded()))m"
  }

  private func metric(value: String, label: String, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(value)
        .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
        .foregroundStyle(color)
        .lineLimit(1)
      Text(label)
        .font(.system(size: 10, weight: .bold, design: .rounded))
        .foregroundStyle(WorkoutLiveActivityStyle.secondaryText)
    }
  }
}

private struct WorkoutLiveActivityElapsedText: View {
  let state: WorkoutLiveActivityAttributes.ContentState

  var body: some View {
    if let timerStartDate = state.timerStartDate {
      Text(timerStartDate, style: .timer)
    } else {
      Text(formattedElapsed)
    }
  }

  private var formattedElapsed: String {
    let totalSeconds = max(Int(state.elapsedSeconds.rounded()), 0)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
      return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
    }
    return "\(minutes):\(String(format: "%02d", seconds))"
  }
}

private extension Color {
  init(hex: String) {
    let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var value: UInt64 = 0
    Scanner(string: sanitized).scanHexInt64(&value)

    let red: Double
    let green: Double
    let blue: Double
    switch sanitized.count {
    case 6:
      red = Double((value & 0xFF0000) >> 16) / 255
      green = Double((value & 0x00FF00) >> 8) / 255
      blue = Double(value & 0x0000FF) / 255
    default:
      red = 0.2
      green = 0.78
      blue = 0.35
    }
    self.init(red: red, green: green, blue: blue)
  }
}

private enum WorkoutLiveActivityStyle {
  static let background = Color.black
  static let secondaryText = Color(red: 0.58, green: 0.58, blue: 0.62)
  static let workoutYellow = Color(red: 1.0, green: 0.91, blue: 0.24)
  static let exerciseGreen = Color(red: 0.62, green: 1.0, blue: 0.12)
  static let movePink = Color(red: 1.0, green: 0.10, blue: 0.34)
  static let standCyan = Color(red: 0.39, green: 0.92, blue: 0.95)
  static let heartRed = Color(red: 1.0, green: 0.23, blue: 0.18)
}
