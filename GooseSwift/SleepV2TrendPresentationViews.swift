import Darwin
import Foundation
import SwiftUI
import UIKit

struct SleepV2MiniBarChart: View {
  let palette: SleepV2Palette
  let points: [Double]
  let tint: Color

  var body: some View {
    GeometryReader { proxy in
      let values = chartValues
      let minValue = values.min() ?? 0
      let maxValue = values.max() ?? 1
      let range = max(maxValue - minValue, 1)
      if values.contains(where: { $0 < 0 }) {
        let domainMin = min(minValue, 0)
        let domainMax = max(maxValue, 0)
        let domainRange = max(domainMax - domainMin, 1)
        let baselineY = yPosition(for: 0, height: proxy.size.height, minValue: domainMin, range: domainRange)
        HStack(alignment: .center, spacing: 6) {
          ForEach(Array(values.enumerated()), id: \.offset) { index, value in
            let valueY = yPosition(for: value, height: proxy.size.height, minValue: domainMin, range: domainRange)
            let barHeight = max(8, abs(valueY - baselineY))
            Capsule()
              .fill(barColor(at: index, count: values.count, value: value))
              .frame(width: 9, height: barHeight)
              .offset(y: (valueY + baselineY) / 2 - proxy.size.height / 2)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
      } else {
        HStack(alignment: .bottom, spacing: 6) {
          ForEach(Array(values.enumerated()), id: \.offset) { index, value in
            let normalized = (value - minValue) / range
            let barHeight = max(18, proxy.size.height * (0.30 + normalized * 0.62))
            Capsule()
              .fill(barColor(at: index, count: values.count, value: value))
              .frame(width: 9, height: barHeight)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
      }
    }
  }

  private var chartValues: [Double] {
    if points.isEmpty {
      return [0.34, 0.44, 0.28, 0.50, 0.38]
    }
    return Array(points.suffix(7))
  }

  private func barColor(at index: Int, count: Int, value: Double) -> Color {
    if points.isEmpty {
      return palette.separator.opacity(0.65)
    }
    if value < 0 {
      return Color(red: 0.95, green: 0.34, blue: 0.20)
        .opacity(index == count - 1 ? 0.96 : 0.64)
    }
    return index == count - 1
      ? tint
      : (palette.light ? Color(red: 0.86, green: 0.87, blue: 0.91) : palette.surfaceHeader)
  }

  private func yPosition(for value: Double, height: CGFloat, minValue: Double, range: Double) -> CGFloat {
    let normalized = (value - minValue) / range
    return height - height * CGFloat(normalized)
  }
}

struct SleepV2Sparkline: View {
  let points: [Double]
  let tint: Color
  var belowThresholdTint: Color?

  var body: some View {
    GeometryReader { proxy in
      if points.isEmpty {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.white.opacity(0.08))
      } else {
        let minimum = points.min() ?? 0
        let maximum = points.max() ?? 1
        let span = max(maximum - minimum, 1)
        ZStack {
          sparklinePath(size: proxy.size, minimum: minimum, span: span)
            .fill(tint.opacity(0.20))
            .offset(y: 16)
          sparklinePath(size: proxy.size, minimum: minimum, span: span)
            .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
          if let last = points.last {
            let point = point(for: last, index: points.count - 1, size: proxy.size, minimum: minimum, span: span)
            Circle()
              .fill(tint.opacity(0.24))
              .frame(width: 24, height: 24)
              .position(point)
            Circle()
              .fill(tint)
              .frame(width: 9, height: 9)
              .position(point)
          }
        }
      }
    }
  }

  private func sparklinePath(size: CGSize, minimum: Double, span: Double) -> Path {
    Path { path in
      guard !points.isEmpty else {
        return
      }
      for (index, value) in points.enumerated() {
        let point = point(for: value, index: index, size: size, minimum: minimum, span: span)
        if index == 0 {
          path.move(to: point)
        } else {
          path.addLine(to: point)
        }
      }
    }
  }

  private func point(for value: Double, index: Int, size: CGSize, minimum: Double, span: Double) -> CGPoint {
    let x = size.width * CGFloat(index) / CGFloat(max(points.count - 1, 1))
    let normalized = (value - minimum) / span
    let y = size.height - size.height * CGFloat(normalized)
    return CGPoint(x: x, y: y)
  }
}

struct SleepV2TrendSheet: View {
  let snapshot: HealthMetricSnapshot
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme
  @State private var selectedRange = "30D"

  var body: some View {
    let palette = SleepV2Palette(colorScheme: colorScheme)
    NavigationStack {
      ScrollView {
	        VStack(alignment: .leading, spacing: 16) {
	          VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
              Image(systemName: snapshot.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(snapshot.tint)
                .frame(width: 42, height: 42)
                .background(snapshot.tint.opacity(0.12), in: Circle())
              VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.title)
                  .font(.title3.weight(.semibold))
                  .foregroundStyle(palette.text)
                Text(snapshot.trend.rangeLabel)
                  .font(.subheadline.weight(.medium))
                  .foregroundStyle(palette.secondaryText)
              }
              Spacer(minLength: 8)
              Text(snapshot.status.localizedHealthStatus)
                .font(.caption.weight(.semibold))
                .foregroundStyle(snapshot.tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(snapshot.tint.opacity(0.12), in: Capsule())
            }

	            VStack(alignment: .leading, spacing: 4) {
	              Text(snapshot.displayValue.replacingOccurrences(of: " %", with: "%"))
	                .font(.system(size: 48, weight: .semibold, design: .rounded))
	                .foregroundStyle(palette.text)
	                .lineLimit(1)
	                .minimumScaleFactor(0.62)
	              Text("Latest value")
	                .font(.footnote.weight(.semibold))
	                .foregroundStyle(palette.secondaryText)
	            }

            Picker("Range", selection: $selectedRange) {
              ForEach(["7D", "30D", "6M"], id: \.self) { range in
                Text(range).tag(range)
              }
	            }
	            .pickerStyle(.segmented)
	            .tint(snapshot.tint)
	          }
	          .padding(20)
	          .background(palette.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
	          .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(palette.separator.opacity(0.70), lineWidth: 1))

          VStack(alignment: .leading, spacing: 16) {
            HStack {
              Text("Trend")
                .font(.headline.weight(.semibold))
                .foregroundStyle(palette.text)
              Spacer()
              Text(snapshot.freshness.uppercased())
                .font(.caption.weight(.semibold))
                .fontDesign(.rounded)
                .foregroundStyle(palette.mutedText)
	            }

	            if snapshot.trend.hasData {
	              SleepV2TrendChart(snapshot: snapshot, palette: palette, tint: snapshot.tint)
	                .frame(height: 230)

	              HStack(spacing: 10) {
	                SleepV2TrendMetricTile(label: "Current", value: snapshot.displayValue, palette: palette)
	                SleepV2TrendMetricTile(label: "Average", value: averageDisplay, palette: palette)
	              }
	              SleepV2TrendMetricTile(label: "Range", value: snapshot.trend.rangeLabel, palette: palette)

              Text(snapshot.trend.summary)
                .font(.subheadline)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            } else {
              ContentUnavailableView(
                "No trend data",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text(snapshot.trend.analysis)
              )
              .frame(maxWidth: .infinity)
              .padding(.vertical, 24)
            }
          }
          .padding(20)
          .background(palette.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(palette.separator.opacity(0.70), lineWidth: 1))

          VStack(alignment: .leading, spacing: 14) {
            Text("Analysis")
              .font(.headline.weight(.semibold))
              .foregroundStyle(palette.text)
            Text(snapshot.trend.analysis)
              .font(.subheadline)
              .foregroundStyle(palette.secondaryText)
              .fixedSize(horizontal: false, vertical: true)

            if !snapshot.trend.resources.isEmpty {
              Divider().overlay(palette.separator)
              ForEach(snapshot.trend.resources, id: \.self) { resource in
                Label(resource, systemImage: "book")
                  .font(.subheadline.weight(.medium))
                  .foregroundStyle(palette.secondaryText)
              }
            }
          }
          .padding(20)
          .background(palette.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(palette.separator.opacity(0.70), lineWidth: 1))
        }
        .padding(18)
      }
      .background(palette.background)
      .navigationTitle(snapshot.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") {
            dismiss()
          }
        }
      }
	    }
	    .presentationDetents([.large])
	  }

	  private var averageDisplay: String {
	    let values = snapshot.trend.points.map(\.value)
	    guard !values.isEmpty else {
	      return "--"
	    }
	    let average = values.reduce(0, +) / Double(values.count)
	    return SleepV2TrendValueFormatter.format(average, snapshot: snapshot)
	  }
	}

enum SleepV2TrendPresentation {
  case line
  case bar
}

extension HealthMetricSnapshot {
  var sleepV2TrendPresentation: SleepV2TrendPresentation {
    id == "sleep-bank-trend" || title == "Sleep Bank" ? .bar : .line
  }
}
