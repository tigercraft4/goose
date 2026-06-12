import SwiftUI

struct HomeTimelineSection: View {
  let sleep: HealthMetricSnapshot
  let activity: HealthMetricSnapshot
  let recovery: HealthMetricSnapshot
  let activities: [ActivityTimelineItem]
  let openSleep: () -> Void
  let openActivity: () -> Void
  let openRecovery: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HomeSectionHeader(title: "Timeline")

      VStack(spacing: 8) {
        ForEach(timelineEntries) { entry in
          HomeTimelineRow(
            time: entry.time,
            title: entry.title,
            subtitle: entry.subtitle,
            systemImage: entry.systemImage,
            tint: entry.tint,
            action: { perform(entry.action) }
          )
          .equatable()
        }
      }
    }
  }

  private var timelineEntries: [HomeTimelineEntry] {
    var entries = [
      HomeTimelineEntry(
        id: "sleep",
        sortMinutes: 6 * 60 + 34,
        time: "06:34",
        title: "Sleep summary",
        subtitle: summary(for: sleep),
        systemImage: "moon.fill",
        tint: sleep.tint,
        action: .sleep
      ),
      HomeTimelineEntry(
        id: "recovery",
        sortMinutes: 17 * 60,
        time: "17:00",
        title: "Recovery update",
        subtitle: summary(for: recovery),
        systemImage: "battery.25",
        tint: recovery.tint,
        action: .recovery
      ),
    ]

    if activities.isEmpty {
      entries.append(
        HomeTimelineEntry(
          id: "activity-load",
          sortMinutes: 12 * 60 + 30,
          time: "12:30",
          title: "Activity load",
          subtitle: summary(for: activity),
          systemImage: "arrow.triangle.2.circlepath",
          tint: activity.tint,
          action: .activity
        )
      )
    } else {
      entries.append(contentsOf: activities.map(activityEntry))
    }
    return entries.sorted { $0.sortMinutes > $1.sortMinutes }
  }

  private func activityEntry(_ item: ActivityTimelineItem) -> HomeTimelineEntry {
    let components = Calendar.current.dateComponents([.hour, .minute], from: item.startedAt)
    let hour = components.hour ?? 0
    let minute = components.minute ?? 0
    return HomeTimelineEntry(
      id: item.id,
      sortMinutes: hour * 60 + minute,
      time: Self.timeFormatter.string(from: item.startedAt),
      title: item.title,
      subtitle: activitySummary(for: item),
      systemImage: systemImage(for: item.activityType),
      tint: tint(for: item.activityType),
      action: .activity
    )
  }

  private func summary(for snapshot: HealthMetricSnapshot) -> String {
    "\(snapshot.displayValue) - \(snapshot.status.localizedHealthStatus)"
  }

  private func activitySummary(for item: ActivityTimelineItem) -> String {
    var parts: [String] = []
    if let distanceMeters = item.distanceMeters, distanceMeters > 0 {
      parts.append(formatDistance(distanceMeters))
    }
    parts.append(formatDuration(item.durationSeconds))
    if let averageHeartRate = item.averageHeartRate {
      parts.append("avg \(averageHeartRate) bpm")
    }
    return parts.joined(separator: " - ")
  }

  private func perform(_ action: HomeTimelineAction) {
    switch action {
    case .sleep:
      openSleep()
    case .activity:
      openActivity()
    case .recovery:
      openRecovery()
    }
  }

  private func systemImage(for activityType: String) -> String {
    switch activityType {
    case "walking", "hiking":
      return "figure.walk"
    case "running":
      return "figure.run"
    case "cycling", "spinning":
      return "bicycle"
    case "strength":
      return "dumbbell"
    default:
      return "figure.mixed.cardio"
    }
  }

  private func tint(for activityType: String) -> Color {
    switch activityType {
    case "walking", "hiking":
      return .green
    case "running":
      return .orange
    case "cycling", "spinning":
      return .blue
    case "strength":
      return .red
    default:
      return activity.tint
    }
  }

  private func formatDistance(_ meters: Double) -> String {
    if meters >= 1000 {
      return String(format: "%.2f km", meters / 1000)
    }
    return "\(Int(meters.rounded())) m"
  }

  private func formatDuration(_ seconds: TimeInterval) -> String {
    let totalSeconds = max(Int(seconds.rounded()), 0)
    let minutes = totalSeconds / 60
    let remainder = totalSeconds % 60
    if minutes >= 60 {
      return String(format: "%d:%02d:%02d", minutes / 60, minutes % 60, remainder)
    }
    return String(format: "%d:%02d", minutes, remainder)
  }

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
  }()
}

struct HomeTimelineEntry: Identifiable, Equatable {
  let id: String
  let sortMinutes: Int
  let time: String
  let title: String
  let subtitle: String
  let systemImage: String
  let tint: Color
  let action: HomeTimelineAction

  static func == (lhs: HomeTimelineEntry, rhs: HomeTimelineEntry) -> Bool {
    lhs.id == rhs.id
      && lhs.sortMinutes == rhs.sortMinutes
      && lhs.time == rhs.time
      && lhs.title == rhs.title
      && lhs.subtitle == rhs.subtitle
      && lhs.systemImage == rhs.systemImage
      && lhs.action == rhs.action
  }
}

enum HomeTimelineAction: Equatable {
  case sleep
  case activity
  case recovery
}

struct HomeTimelineRow: View, Equatable {
  let time: String
  let title: String
  let subtitle: String
  let systemImage: String
  let tint: Color
  let action: () -> Void

  static func == (lhs: HomeTimelineRow, rhs: HomeTimelineRow) -> Bool {
    lhs.time == rhs.time
      && lhs.title == rhs.title
      && lhs.subtitle == rhs.subtitle
      && lhs.systemImage == rhs.systemImage
  }

  var body: some View {
    Button {
      action()
    } label: {
      HStack(spacing: 12) {
        Image(systemName: systemImage)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(tint)
          .frame(width: 36, height: 36)
          .background(tint.opacity(0.12), in: Circle())

        VStack(alignment: .leading, spacing: 3) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
              .font(.subheadline.weight(.bold))
              .foregroundStyle(.primary)
              .lineLimit(1)

            Spacer(minLength: 8)

            Text(time)
              .font(.caption.weight(.bold))
              .foregroundStyle(.secondary)
              .monospacedDigit()
              .lineLimit(1)
          }

          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Image(systemName: "chevron.right")
          .font(.caption.weight(.bold))
          .foregroundStyle(.tertiary)
      }
      .padding(14)
      .cardSurface(tint: tint)
    }
    .buttonStyle(.plain)
  }
}

struct HomeSectionHeader: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.title3.bold())
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, 4)
  }
}

extension View {
  func cardSurface(tint: Color = .green, prominent: Bool = false) -> some View {
    modifier(HomeCardSurfaceModifier(tint: tint, prominent: prominent))
  }
}

struct HomeCardSurfaceModifier: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme
  let tint: Color
  let prominent: Bool

  func body(content: Content) -> some View {
    content
      .background {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(baseFill)
          .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .fill(
                LinearGradient(
                  colors: [
                    tint.opacity(tintOpacity),
                    tint.opacity(tintOpacity * 0.36),
                    .clear,
                  ],
                  startPoint: .topLeading,
                  endPoint: .bottomTrailing
                )
              )
          }
      }
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(tint.opacity(borderOpacity), lineWidth: 1)
      }
      .shadow(color: shadowColor, radius: prominent ? 5 : 2, x: 0, y: prominent ? 3 : 1)
  }

  private var baseFill: Color {
    colorScheme == .dark
      ? Color.white.opacity(prominent ? 0.070 : 0.055)
      : Color(UIColor.secondarySystemGroupedBackground)
  }

  private var tintOpacity: Double {
    if colorScheme == .dark {
      prominent ? 0.085 : 0.055
    } else {
      prominent ? 0.040 : 0.024
    }
  }

  private var borderOpacity: Double {
    colorScheme == .dark ? 0.14 : 0.075
  }

  private var shadowColor: Color {
    colorScheme == .dark ? .black.opacity(0.10) : .black.opacity(prominent ? 0.026 : 0.014)
  }
}

