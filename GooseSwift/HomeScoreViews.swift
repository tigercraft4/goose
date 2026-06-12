import SwiftUI

struct HomeTopScrollFade: View {
  var body: some View {
    GeometryReader { proxy in
      LinearGradient(
        stops: [
          .init(color: GooseTheme.appBackground, location: 0),
          .init(color: GooseTheme.appBackground.opacity(0.96), location: 0.56),
          .init(color: GooseTheme.appBackground.opacity(0), location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .frame(height: max(proxy.safeAreaInsets.top + 44, 82))
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .ignoresSafeArea(edges: .top)
    }
  }
}

struct HomeStartActivityFloatingButton: View {
  @ObservedObject var session: ActivitySessionModel

  var body: some View {
    NavigationLink {
      LiveActivityView()
    } label: {
      Image(systemName: session.isActive ? session.selectedActivity.systemImage : "plus")
        .font(.system(size: 21, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 54, height: 54)
        .background(session.selectedActivity.tint, in: Circle())
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 7)
        .overlay {
          Circle()
            .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(session.isActive ? "Open Activity" : "Start Activity")
  }
}

struct HomeDailyScoreCard: View {
  let scores: [HealthMetricSnapshot]
  let coachTip: CoachInlineTip
  let openScore: (HealthRoute) -> Void
  let openCoach: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        ForEach(scores) { score in
          Button {
            openScore(score.route)
          } label: {
            HomeScoreDial(snapshot: score)
          }
          .buttonStyle(.plain)
        }
      }
      .frame(maxWidth: .infinity)

      CoachTipCard(tip: coachTip) {
        openCoach(coachTip.prompt)
      }
      .padding(.top, 2)
    }
  }
}

struct HomeScoreDial: View {
  let snapshot: HealthMetricSnapshot

  var body: some View {
    VStack(spacing: 9) {
      ZStack {
        Circle()
          .stroke(snapshot.tint.opacity(0.14), lineWidth: 9)
        Circle()
          .trim(from: 0, to: progress)
          .stroke(snapshot.tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
          .rotationEffect(.degrees(-90))

        Text(scoreText)
          .font(.system(size: 24, weight: .bold, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.62)
          .padding(8)
      }
      .frame(width: 88, height: 88)

      HStack(spacing: 4) {
        Image(systemName: snapshot.systemImage)
          .font(.caption.weight(.bold))
          .foregroundStyle(snapshot.tint)
        Text(snapshot.title)
          .font(.caption.weight(.bold))
          .foregroundStyle(.primary)
      }
      .lineLimit(1)
      .minimumScaleFactor(0.75)
      .padding(.top, 2)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }

  private var scoreText: String {
    snapshot.displayValue
      .replacingOccurrences(of: "%", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var progress: Double {
    let value = firstNumber(in: snapshot.displayValue) ?? 0
    return min(max(value / 100, 0), 1)
  }
}

struct HomeStressEnergySection: View {
  let stress: HealthMetricSnapshot
  let energy: HealthMetricSnapshot
  let openStress: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HomeSectionHeader(title: "Stress & Energy")

      Button {
        openStress()
      } label: {
        HStack(spacing: 14) {
          VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
              Circle()
                .fill(stress.tint)
                .frame(width: 10, height: 10)
              Text("Today's stress")
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
              Spacer()
            }

            Text(stress.freshness)
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)

            HStack(spacing: 12) {
              HomeStressStat(value: highestStressText, label: "Highest", color: .red)
              HomeStressStat(value: lowestStressText, label: "Lowest", color: .cyan)
              HomeStressStat(value: averageStressText, label: "Average", color: .green)
            }
          }

          ZStack {
            Circle()
              .stroke(stress.tint.opacity(0.14), lineWidth: 8)
            Circle()
              .trim(from: 0, to: stressProgress)
              .stroke(stress.tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
              .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
              Text(stress.value)
                .font(.title3.bold())
              Text(stress.status)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          .frame(width: 76, height: 76)

          Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(.tertiary)
        }
        .padding(14)
        .cardSurface(tint: stress.tint, prominent: true)
      }
      .buttonStyle(.plain)

      HomeEnergyBar(percent: Int(firstNumber(in: energy.displayValue) ?? 0), caption: energy.status)
    }
  }

  private var stressProgress: Double {
    min(max((firstNumber(in: stress.displayValue) ?? 0) / 100, 0), 1)
  }

  private var stressValues: [Double] {
    stress.trend.points.map(\.value)
  }

  private var highestStressText: String {
    stressValues.max().map { "\(Int($0.rounded()))" } ?? "--"
  }

  private var lowestStressText: String {
    stressValues.min().map { "\(Int($0.rounded()))" } ?? "--"
  }

  private var averageStressText: String {
    firstNumber(in: stress.value).map { "\(Int($0.rounded()))" } ?? "--"
  }
}

struct HomeStressStat: View {
  let value: String
  let label: String
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value)
        .font(.headline.bold())
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
      Text(label)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct HomeEnergyBar: View {
  let percent: Int
  let caption: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "bolt.fill")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.green)
        .frame(width: 30, height: 30)
        .background(.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

      HStack(spacing: 3) {
        ForEach(0..<18, id: \.self) { index in
          RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(index < filledSegments ? Color.green : Color.primary.opacity(0.12))
            .frame(height: 18)
        }
      }

      VStack(alignment: .trailing, spacing: 2) {
        Text("\(percent)%")
          .font(.headline.bold())
          .lineLimit(1)
        Text(caption)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(14)
    .cardSurface(tint: .green)
  }

  private var filledSegments: Int {
    Int((Double(percent) / 100 * 18).rounded())
  }
}

struct HomeCardioLoadWidget: View {
  let snapshot: HealthMetricSnapshot
  let days: [CardioLoadDay]
  let openSheet: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HomeSectionHeader(title: "Cardio Load")

      Button(action: openSheet) {
        VStack(alignment: .leading, spacing: 16) {
          HStack(spacing: 10) {
            Image(systemName: "shoeprints.fill")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(.pink)
              .frame(width: 32, height: 32)
              .background(.pink.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text("Cardio Load")
              .font(.headline)
              .foregroundStyle(.primary)
              .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
              .font(.caption.weight(.bold))
              .foregroundStyle(.tertiary)
          }

          HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
              Text(valueText)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

              Text(statusText)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
            .frame(width: 96, alignment: .leading)

            HomeCardioLoadSparkline(days: days)
              .frame(height: 82)
              .frame(maxWidth: .infinity)
          }
        }
        .padding(14)
        .cardSurface(tint: .pink, prominent: true)
      }
      .buttonStyle(.plain)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Cardio Load, \(valueText), \(statusText)")
    }
  }

  private var valueText: String {
    if let latest = days.last {
      return "\(Int(latest.load.rounded()))"
    }
    return snapshot.value
  }

  private var statusText: String {
    days.last?.status ?? snapshot.status
  }
}

