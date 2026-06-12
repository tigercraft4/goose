import SwiftUI

struct HomeCardioLoadSparkline: View {
  let days: [CardioLoadDay]

  var body: some View {
    GeometryReader { proxy in
      if values.isEmpty {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.primary.opacity(0.06))
          .overlay {
            Text("No data")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
          }
      } else {
        ZStack(alignment: .bottomLeading) {
          rangeBandPath(in: proxy.size)
            .fill(Color.pink.opacity(0.12))

          sparklinePath(in: proxy.size)
            .stroke(
              Color.pink.opacity(0.92),
              style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )

          if let last = values.last {
            let lastPoint = chartPoint(index: values.count - 1, value: last, size: proxy.size)
            Circle()
              .fill(GooseTheme.appBackground)
              .frame(width: 18, height: 18)
              .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 2)
              .position(lastPoint)
            Circle()
              .stroke(Color.pink, lineWidth: 3)
              .frame(width: 11, height: 11)
              .position(lastPoint)
          }
        }
      }
    }
  }

  private var values: [Double] {
    days.map(\.load)
  }

  private func sparklinePath(in size: CGSize) -> Path {
    Path { path in
      for (index, value) in values.enumerated() {
        let point = chartPoint(index: index, value: value, size: size)
        if index == 0 {
          path.move(to: point)
        } else {
          path.addLine(to: point)
        }
      }
    }
  }

  private func rangeBandPath(in size: CGSize) -> Path {
    var upperPoints: [CGPoint] = []
    var lowerPoints: [CGPoint] = []
    for (index, value) in values.enumerated() {
      upperPoints.append(chartPoint(index: index, value: value * 1.14 + 4, size: size))
      lowerPoints.append(chartPoint(index: index, value: max(value * 0.74 - 3, 0), size: size))
    }

    return Path { path in
      guard let first = upperPoints.first else { return }
      path.move(to: first)
      upperPoints.dropFirst().forEach { path.addLine(to: $0) }
      lowerPoints.reversed().forEach { path.addLine(to: $0) }
      path.closeSubpath()
    }
  }

  private func chartPoint(index: Int, value: Double, size: CGSize) -> CGPoint {
    let left: CGFloat = 4
    let right: CGFloat = 16
    let top: CGFloat = 10
    let bottom: CGFloat = 12
    let maximum = max((values.max() ?? 1) * 1.20, 60)
    let x = left + (size.width - left - right) * CGFloat(index) / CGFloat(max(values.count - 1, 1))
    let normalized = min(max(value / maximum, 0), 1)
    let y = top + (size.height - top - bottom) * CGFloat(1 - normalized)
    return CGPoint(x: x, y: y)
  }
}

struct HomeHealthMonitorSection: View {
  let snapshots: [HealthMetricSnapshot]
  let openSnapshot: (HealthMetricSnapshot) -> Void

  private let columns = [
    GridItem(.flexible(), spacing: 10),
    GridItem(.flexible(), spacing: 10),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HomeSectionHeader(title: "Health Monitor")

      LazyVGrid(columns: columns, spacing: 10) {
        ForEach(snapshots) { snapshot in
          Button {
            openSnapshot(snapshot)
          } label: {
            HomeHealthMetricCard(snapshot: snapshot)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}

struct HomeHealthMetricCard: View {
  let snapshot: HealthMetricSnapshot

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 6) {
          Image(systemName: snapshot.systemImage)
            .foregroundStyle(snapshot.tint)
          Text(snapshot.title)
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }

        Spacer(minLength: 4)

        Text(snapshot.displayValue)
          .font(.title3.bold())
          .foregroundStyle(.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.65)

        Label(snapshot.status.localizedHealthStatus, systemImage: statusImage)
          .font(.caption.weight(.bold))
          .foregroundStyle(snapshot.tint)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }

      Spacer(minLength: 0)

      Capsule()
        .fill(snapshot.tint.opacity(0.18))
        .frame(width: 8)
        .overlay(alignment: .bottom) {
          Capsule()
            .fill(snapshot.tint)
            .frame(height: 52)
        }
    }
    .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
    .padding(12)
    .cardSurface(tint: snapshot.tint)
  }

  private var statusImage: String {
    snapshot.status.localizedCaseInsensitiveContains("unavailable") ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
  }
}

