import Darwin
import Foundation
import SwiftUI
import UIKit

struct RecoveryV2ScenicBackground: View {
  let palette: SleepV2Palette

  var body: some View {
    ZStack {
      LinearGradient(
        colors: palette.light
          ? [
              Color(red: 0.84, green: 0.93, blue: 0.87),
              Color(red: 0.72, green: 0.86, blue: 0.77),
              palette.background,
            ]
          : [
              Color(red: 0.06, green: 0.12, blue: 0.10),
              Color(red: 0.09, green: 0.18, blue: 0.13),
              palette.background,
            ],
        startPoint: .top,
        endPoint: .bottom
      )

      Canvas { context, size in
        let primaryBand = filledRecoveryBand(
          size: size,
          y: size.height * 0.24,
          height: size.height * 0.15,
          lift: size.height * 0.03
        )
        context.fill(
          primaryBand,
          with: .color(Color(red: 0.36, green: 0.78, blue: 0.48).opacity(palette.light ? 0.20 : 0.16))
        )

        let secondaryBand = filledRecoveryBand(
          size: size,
          y: size.height * 0.38,
          height: size.height * 0.12,
          lift: size.height * 0.02
        )
        context.fill(
          secondaryBand,
          with: .color(Color(red: 0.66, green: 0.90, blue: 0.70).opacity(palette.light ? 0.16 : 0.10))
        )

        let signalPath = recoverySignalPath(
          size: size,
          y: size.height * 0.34,
          amplitude: size.height * 0.035
        )
        context.stroke(
          signalPath,
          with: .color(Color(red: 0.54, green: 0.92, blue: 0.60).opacity(palette.light ? 0.24 : 0.20)),
          style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )
      }

      VStack {
        Spacer()
        Rectangle()
          .fill(
            LinearGradient(
              colors: [.clear, palette.background.opacity(0.72), palette.background],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .frame(height: 150)
      }
    }
  }

  private func filledRecoveryBand(size: CGSize, y: CGFloat, height: CGFloat, lift: CGFloat) -> Path {
    let width = max(size.width, 1)
    let left = -width * 0.08
    let right = width * 1.08
    let top = y
    let bottom = y + height

    var path = Path()
    path.move(to: CGPoint(x: left, y: top + lift))
    path.addCurve(
      to: CGPoint(x: width * 0.46, y: top),
      control1: CGPoint(x: width * 0.10, y: top + lift * 2.4),
      control2: CGPoint(x: width * 0.26, y: top - lift * 0.9)
    )
    path.addCurve(
      to: CGPoint(x: right, y: top + lift * 1.2),
      control1: CGPoint(x: width * 0.68, y: top + lift * 2.0),
      control2: CGPoint(x: width * 0.88, y: top - lift * 0.8)
    )
    path.addLine(to: CGPoint(x: right, y: bottom + lift))
    path.addCurve(
      to: CGPoint(x: width * 0.48, y: bottom),
      control1: CGPoint(x: width * 0.88, y: bottom - lift * 0.7),
      control2: CGPoint(x: width * 0.70, y: bottom + lift * 1.8)
    )
    path.addCurve(
      to: CGPoint(x: left, y: bottom + lift * 0.6),
      control1: CGPoint(x: width * 0.26, y: bottom - lift * 1.2),
      control2: CGPoint(x: width * 0.08, y: bottom + lift * 1.4)
    )
    path.closeSubpath()
    return path
  }

  private func recoverySignalPath(size: CGSize, y: CGFloat, amplitude: CGFloat) -> Path {
    let width = max(size.width, 1)

    var path = Path()
    path.move(to: CGPoint(x: -width * 0.05, y: y))
    path.addCurve(
      to: CGPoint(x: width * 0.32, y: y - amplitude),
      control1: CGPoint(x: width * 0.06, y: y + amplitude * 0.85),
      control2: CGPoint(x: width * 0.18, y: y - amplitude * 1.25)
    )
    path.addCurve(
      to: CGPoint(x: width * 0.67, y: y + amplitude * 0.42),
      control1: CGPoint(x: width * 0.46, y: y + amplitude * 0.25),
      control2: CGPoint(x: width * 0.54, y: y + amplitude * 1.2)
    )
    path.addCurve(
      to: CGPoint(x: width * 1.05, y: y - amplitude * 0.24),
      control1: CGPoint(x: width * 0.80, y: y - amplitude * 0.62),
      control2: CGPoint(x: width * 0.92, y: y - amplitude * 0.84)
    )
    return path
  }
}

struct RecoveryV2TrendCard: View {
  let palette: SleepV2Palette
  let snapshot: HealthMetricSnapshot
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 9) {
            Image(systemName: snapshot.systemImage)
              .font(.headline.weight(.semibold))
            Text(snapshot.title)
              .font(.headline.weight(.semibold))
              .lineLimit(1)
              .minimumScaleFactor(0.70)
          }
          .foregroundStyle(palette.mutedText)

          HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(valueText)
              .font(.system(size: 42, weight: .regular, design: .rounded))
              .foregroundStyle(palette.text)
              .lineLimit(1)
              .minimumScaleFactor(0.64)
            if !unitText.isEmpty {
              Text(unitText)
                .font(.title2.weight(.semibold))
                .foregroundStyle(palette.mutedText)
            }
          }

          HStack(spacing: 7) {
            Image(systemName: statusIcon)
              .font(.title3.weight(.bold))
            Text(statusText)
              .font(.title3.weight(.semibold))
              .lineLimit(1)
              .minimumScaleFactor(0.72)
          }
          .foregroundStyle(statusColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)

        ZStack(alignment: .topTrailing) {
          RecoveryV2TrendBand(snapshot: snapshot, palette: palette, tint: statusColor)
            .frame(width: 106, height: 66)
            .padding(.top, 26)
            .padding(.trailing, 4)

          Image(systemName: "arrow.right")
            .font(.title2.weight(.medium))
            .foregroundStyle(palette.mutedText.opacity(0.80))
        }
        .frame(width: 122, height: 112)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 18)
      .frame(maxWidth: .infinity, minHeight: 152, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 28, style: .continuous)
          .fill(cardFill)
          .shadow(color: palette.shadow.opacity(0.46), radius: 12, x: 0, y: 5)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 28, style: .continuous)
          .stroke(palette.separator.opacity(0.70), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
  }

  private var cardFill: Color {
    palette.surfaceElevated
  }

  private var valueText: String {
    let trimmed = snapshot.value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasSuffix("%") {
      return String(trimmed.dropLast())
    }
    return trimmed.isEmpty ? "0" : trimmed
  }

  private var unitText: String {
    if snapshot.value.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("%") || snapshot.unit == "%" {
      return "%"
    }
    return snapshot.unit
  }

  private var statusText: String {
    snapshot.status.localizedCaseInsensitiveContains("no data") ? "No data" : snapshot.status
  }

  private var statusIcon: String {
    snapshot.trend.hasData ? "checkmark.circle.fill" : "arrow.down.circle.fill"
  }

  private var statusColor: Color {
    if !snapshot.trend.hasData {
      return palette.mutedText
    }
    return snapshot.status.localizedCaseInsensitiveContains("below")
      ? Color(red: 0.94, green: 0.62, blue: 0.22)
      : palette.accent
  }
}

struct RecoveryV2TrendBand: View {
  let snapshot: HealthMetricSnapshot
  let palette: SleepV2Palette
  let tint: Color

  var body: some View {
    GeometryReader { proxy in
      let rect = CGRect(origin: .zero, size: proxy.size)
      let values = chartValues
      let domain = valueDomain(values)

      ZStack {
        normalBand(in: rect)
          .fill(bandColor)

        trendPath(values: values, in: rect, domain: domain)
          .stroke(lineColor, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

        if let last = values.indices.last {
          let point = point(for: values[last], index: last, count: values.count, in: rect, domain: domain)
          Circle()
            .fill(lineColor.opacity(snapshot.trend.hasData ? 0.24 : 0.12))
            .blur(radius: snapshot.trend.hasData ? 9 : 2)
            .frame(width: 46, height: 46)
            .position(point)
          Circle()
            .stroke(lineColor, lineWidth: 4)
            .background(Circle().fill(cardInnerFill))
            .frame(width: 20, height: 20)
            .position(point)
        }
      }
    }
  }

  private var chartValues: [Double] {
    let values = snapshot.trend.points.map(\.value)
    return values.isEmpty ? [0, 0, 0, 0, 0, 0] : Array(values.suffix(24))
  }

  private var lineColor: Color {
    snapshot.trend.hasData ? tint : palette.mutedText.opacity(0.54)
  }

  private var bandColor: Color {
    snapshot.trend.hasData
      ? Color(red: 0.29, green: 0.58, blue: 0.43).opacity(0.56)
      : palette.separator.opacity(0.70)
  }

  private var cardInnerFill: Color {
    palette.light ? Color(red: 0.93, green: 0.94, blue: 0.97) : Color(red: 0.20, green: 0.21, blue: 0.26)
  }

  private func valueDomain(_ values: [Double]) -> (min: Double, max: Double) {
    let minValue = values.min() ?? 0
    let maxValue = values.max() ?? 0
    guard minValue != maxValue else {
      return (minValue - 1, maxValue + 1)
    }
    let padding = max((maxValue - minValue) * 0.18, 1)
    return (minValue - padding, maxValue + padding)
  }

  private func normalBand(in rect: CGRect) -> Path {
    var path = Path()
    let left = rect.minX + 4
    let right = rect.maxX - 6
    let mid = rect.midY
    let topInset = rect.height * 0.24
    let bottomInset = rect.height * 0.22

    path.move(to: CGPoint(x: left, y: mid - topInset))
    path.addCurve(
      to: CGPoint(x: right, y: mid - topInset * 0.66),
      control1: CGPoint(x: rect.midX * 0.70, y: rect.minY + topInset * 0.38),
      control2: CGPoint(x: rect.midX * 1.18, y: rect.minY + topInset * 0.66)
    )
    path.addLine(to: CGPoint(x: right, y: mid + bottomInset * 0.74))
    path.addCurve(
      to: CGPoint(x: left, y: mid + bottomInset),
      control1: CGPoint(x: rect.midX * 1.24, y: rect.maxY - bottomInset * 0.32),
      control2: CGPoint(x: rect.midX * 0.66, y: rect.maxY - bottomInset * 0.48)
    )
    path.closeSubpath()
    return path
  }

  private func trendPath(values: [Double], in rect: CGRect, domain: (min: Double, max: Double)) -> Path {
    var path = Path()
    for (index, value) in values.enumerated() {
      let point = point(for: value, index: index, count: values.count, in: rect, domain: domain)
      if index == 0 {
        path.move(to: point)
      } else {
        path.addLine(to: point)
      }
    }
    return path
  }

  private func point(
    for value: Double,
    index: Int,
    count: Int,
    in rect: CGRect,
    domain: (min: Double, max: Double)
  ) -> CGPoint {
    let span = max(domain.max - domain.min, 1)
    let x = rect.minX + CGFloat(index) / CGFloat(max(count - 1, 1)) * rect.width
    let normalized = (value - domain.min) / span
    let y = rect.maxY - CGFloat(normalized) * rect.height
    return CGPoint(x: x, y: y)
  }
}

// MARK: - ReadinessLevelCard

// MARK: - V24BiometricsCard

struct V24BiometricsCard: View {
  let palette: SleepV2Palette
  let result: V24BiometricsResult

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: "sensor.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(palette.accent)
        Text("V24 Biometrics")
          .font(.headline.weight(.semibold))
          .foregroundStyle(palette.text)
        Spacer()
        Text("uncalibrated")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(Color.orange.opacity(0.84), in: Capsule())
      }

      HStack(spacing: 0) {
        V24MetricCell(
          palette: palette,
          systemImage: "drop.fill",
          label: "SpO₂",
          value: result.spo2Text,
          tint: .blue
        )
        Divider().frame(maxHeight: 48).background(palette.separator.opacity(0.54))
        V24MetricCell(
          palette: palette,
          systemImage: "thermometer.medium",
          label: "Skin temp",
          value: result.skinTempText,
          tint: .orange
        )
        Divider().frame(maxHeight: 48).background(palette.separator.opacity(0.54))
        V24MetricCell(
          palette: palette,
          systemImage: "lungs.fill",
          label: "Resp",
          value: result.respRateText,
          tint: .teal
        )
      }
    }
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(palette.surface)
        .shadow(color: palette.shadow.opacity(0.30), radius: 8, x: 0, y: 3)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(palette.separator.opacity(0.54), lineWidth: 1)
    )
  }
}

struct V24MetricCell: View {
  let palette: SleepV2Palette
  let systemImage: String
  let label: String
  let value: String
  let tint: Color

  var body: some View {
    VStack(spacing: 5) {
      Image(systemName: systemImage)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(tint)
      Text(value)
        .font(.subheadline.weight(.semibold))
        .fontDesign(.rounded)
        .foregroundStyle(value == "--" ? palette.mutedText : palette.text)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
      Text(label)
        .font(.caption2.weight(.medium))
        .foregroundStyle(palette.mutedText)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 6)
  }
}

// MARK: - ReadinessLevelCard

struct ReadinessLevelCard: View {
  let palette: SleepV2Palette
  let result: ReadinessResult?

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: result?.levelIcon ?? "questionmark.circle")
        .font(.title2.weight(.semibold))
        .foregroundStyle(result?.levelColor ?? palette.mutedText)
        .frame(width: 36)

      VStack(alignment: .leading, spacing: 4) {
        Text("Readiness")
          .font(.caption.weight(.semibold))
          .foregroundStyle(palette.mutedText)
        Text(result?.levelLabel ?? "Insufficient data")
          .font(.headline.weight(.semibold))
          .foregroundStyle(result != nil ? (result?.levelColor ?? palette.text) : palette.secondaryText)
          .lineLimit(1)
          .minimumScaleFactor(0.80)
      }

      Spacer(minLength: 8)

      if let r = result, !r.insufficientData {
        VStack(alignment: .trailing, spacing: 4) {
          Text(r.acwrZoneLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.secondaryText)
          if let acwr = r.acwr {
            Text(String(format: "ACWR %.2f", acwr))
              .font(.caption2.weight(.medium))
              .foregroundStyle(palette.mutedText)
          }
        }
      } else {
        Text("< 28 days of data")
          .font(.caption.weight(.medium))
          .foregroundStyle(palette.mutedText)
          .lineLimit(2)
          .multilineTextAlignment(.trailing)
      }
    }
    .padding(.horizontal, 14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(palette.surface)
        .shadow(color: palette.shadow.opacity(0.30), radius: 8, x: 0, y: 3)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(
          (result?.levelColor ?? palette.separator).opacity(result != nil && !(result?.insufficientData ?? true) ? 0.54 : 0.28),
          lineWidth: 1
        )
    )
  }
}
