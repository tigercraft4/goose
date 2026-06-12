import Darwin
import Foundation
import SwiftUI
import UIKit

struct SleepV2BevelTrendSheet: View {
  let snapshot: HealthMetricSnapshot
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme
  @State private var selectedRange = "6M"
  @State private var selectedMetricTitle: String?
  @State private var selectedPoint: SleepV2BevelTrendSelection?
  @State private var showingCalendarPicker = false
  @State private var selectedAnchorDate = Date()
  private let ranges = ["1D", "30D", "3M", "6M", "1Y"]

  var body: some View {
    let palette = SleepV2Palette(colorScheme: colorScheme)
    let currentSnapshot = activeSnapshot

    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          summaryHeader(snapshot: currentSnapshot, palette: palette)
          metricPills(palette: palette)

          if currentSnapshot.trend.hasData {
            SleepV2BevelTrendChart(
              snapshot: currentSnapshot,
              palette: palette,
              tint: currentSnapshot.tint,
              selectedRange: selectedRange,
              anchorDate: selectedAnchorDate,
              selection: $selectedPoint
            )
            .frame(height: 320)
          } else {
            ContentUnavailableView(
              "No trend data",
              systemImage: "chart.line.uptrend.xyaxis",
              description: Text(currentSnapshot.trend.analysis)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
          }

          SleepV2BevelRangeSelector(
            ranges: ranges,
            selection: $selectedRange,
            palette: palette,
            onCalendarTap: { showingCalendarPicker = true }
          )
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 24)

        Divider().overlay(palette.separator)

        VStack(alignment: .leading, spacing: 24) {
          if currentSnapshot.trend.hasData {
            SleepV2BevelWeeklyDistribution(snapshot: currentSnapshot, palette: palette, tint: currentSnapshot.tint)

            Text("Trends Analysis")
              .font(.title3.weight(.semibold))
              .foregroundStyle(palette.text)

            SleepV2BevelAnalysisTable(snapshot: currentSnapshot, palette: palette, tint: currentSnapshot.tint)
          } else {
            VStack(alignment: .leading, spacing: 10) {
              Text("Trends Analysis")
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.text)
              Text(currentSnapshot.trend.analysis)
                .font(.body)
                .foregroundStyle(palette.secondaryText)
            }
          }

          if !currentSnapshot.trend.resources.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
              Text("Resources")
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.text)
              ForEach(currentSnapshot.trend.resources, id: \.self) { resource in
                Label(resource, systemImage: "book")
                  .font(.subheadline.weight(.medium))
                  .foregroundStyle(palette.secondaryText)
              }
            }
          }
        }
        .padding(.horizontal, 18)
        .padding(.top, 24)
        .padding(.bottom, 40)
      }
      .background(palette.background.ignoresSafeArea())
      .navigationTitle(currentSnapshot.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .foregroundStyle(palette.text)
        }
      }
    }
    .presentationDetents([.large])
    .onAppear {
      selectedMetricTitle = selectedMetricTitle ?? snapshot.title
    }
    .sheet(isPresented: $showingCalendarPicker) {
      NavigationStack {
        DatePicker(
          "Trend end date",
          selection: $selectedAnchorDate,
          displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .padding()
        .navigationTitle("Trend Date")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
              selectedPoint = nil
              showingCalendarPicker = false
            }
          }
        }
      }
      .presentationDetents([.medium])
    }
  }

  @ViewBuilder private func summaryHeader(snapshot: HealthMetricSnapshot, palette: SleepV2Palette) -> some View {
    let selectedValue = selectedPoint.map { SleepV2TrendValueFormatter.format($0.value, snapshot: snapshot) }
    let value = selectedValue ?? snapshot.displayValue.replacingOccurrences(of: " %", with: "%")
    let dateText = selectedPoint.map { selectedDateText($0.date) } ?? headlineDateRange

    HStack(alignment: .bottom) {
      VStack(alignment: .leading, spacing: 4) {
        Text(value)
          .font(.system(size: 40, weight: .semibold, design: .rounded))
          .foregroundStyle(palette.text)
          .lineLimit(1)
          .minimumScaleFactor(0.62)
        Text(dateText)
          .font(.callout.weight(.semibold))
          .fontDesign(.rounded)
          .foregroundStyle(palette.secondaryText)
      }

      Spacer(minLength: 12)

      VStack(alignment: .trailing, spacing: 6) {
        if let selectedPoint {
          Text("vs avg")
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.secondaryText)
          Text(deltaText(for: selectedPoint.value, snapshot: snapshot))
            .font(.callout.weight(.semibold))
            .fontDesign(.rounded)
            .foregroundStyle(deltaColor(for: selectedPoint.value, snapshot: snapshot))
        } else if snapshot.trend.hasData {
          Text("avg")
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.secondaryText)
          Text(SleepV2TrendValueFormatter.format(averageValue(for: snapshot), snapshot: snapshot))
            .font(.callout.weight(.semibold))
            .fontDesign(.rounded)
            .foregroundStyle(palette.text)
          Text(snapshot.status.localizedHealthStatus)
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusColor(for: snapshot))
        } else {
          Text(snapshot.status.localizedHealthStatus)
            .font(.callout.weight(.semibold))
            .foregroundStyle(statusColor(for: snapshot))
          HStack(spacing: 6) {
            Image(systemName: "ruler")
              .font(.caption.weight(.semibold))
            Text(snapshot.trend.rangeLabel)
              .font(.callout.weight(.semibold))
              .fontDesign(.rounded)
          }
          .foregroundStyle(palette.text)
        }
      }
    }
  }

  @ViewBuilder private func metricPills(palette: SleepV2Palette) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        ForEach(metricSnapshots) { metric in
          Button {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
              selectedMetricTitle = metric.title
              selectedPoint = nil
            }
          } label: {
            SleepV2BevelMetricPill(
              title: metric.title,
              selected: metric.title == activeSnapshot.title,
              palette: palette
            )
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 18)
    }
    .padding(.horizontal, -18)
  }

  private var metricSnapshots: [HealthMetricSnapshot] {
    guard snapshot.route == .sleep else {
      return [snapshot]
    }
    return HealthDataStore.sleepTrendRows.filter { $0.trend.hasData || $0.title == snapshot.title }
  }

  private var activeSnapshot: HealthMetricSnapshot {
    let selectedTitle = selectedMetricTitle ?? snapshot.title
    return metricSnapshots.first { $0.title == selectedTitle } ?? snapshot
  }

  private var headlineDateRange: String {
    let calendar = Calendar.current
    let end = selectedAnchorDate
    let days: Int
    switch selectedRange {
    case "1D": return end.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
    case "30D": days = 29
    case "3M": days = 89
    case "1Y": days = 364
    default: days = 182
    }
    let start = calendar.date(byAdding: .day, value: -days, to: end) ?? end
    return "\(start.formatted(.dateTime.day().month(.abbreviated))) - \(end.formatted(.dateTime.day().month(.abbreviated).year()))"
  }

  private func selectedDateText(_ date: Date) -> String {
    if selectedRange == "1D" {
      return date.formatted(.dateTime.weekday(.abbreviated).hour(.twoDigits(amPM: .abbreviated)).day().month(.abbreviated))
    }
    return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
  }

  private func statusColor(for snapshot: HealthMetricSnapshot) -> Color {
    snapshot.status.localizedCaseInsensitiveContains("debt")
      ? Color(red: 1.0, green: 0.50, blue: 0.28)
      : Color(red: 0.43, green: 0.82, blue: 0.52)
  }

  private func deltaText(for value: Double, snapshot: HealthMetricSnapshot) -> String {
    let delta = value - averageValue(for: snapshot)
    let sign = delta >= 0 ? "+" : "-"
    return "\(sign)\(SleepV2TrendValueFormatter.format(abs(delta), snapshot: snapshot))"
  }

  private func deltaColor(for value: Double, snapshot: HealthMetricSnapshot) -> Color {
    let delta = value - averageValue(for: snapshot)
    let favorable = lowerIsBetter(snapshot) ? delta <= 0 : delta >= 0
    return favorable ? Color(red: 0.43, green: 0.82, blue: 0.52) : Color(red: 1.0, green: 0.50, blue: 0.28)
  }

  private func averageValue(for snapshot: HealthMetricSnapshot) -> Double {
    let values = snapshot.trend.points.map(\.value)
    return values.reduce(0, +) / Double(max(values.count, 1))
  }

  private func lowerIsBetter(_ snapshot: HealthMetricSnapshot) -> Bool {
    let title = snapshot.title.lowercased()
    return (title.contains("resting hr") && !title.contains("hrv"))
      || title.contains("stress")
      || title.contains("sleep debt")
      || title.contains("time to fall asleep")
  }
}

struct SleepV2BevelMetricPill: View {
  let title: String
  let selected: Bool
  let palette: SleepV2Palette

  var body: some View {
    Text(title)
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(selected ? palette.text : palette.secondaryText.opacity(0.72))
      .padding(.horizontal, 16)
      .padding(.vertical, 9)
      .background(Capsule().fill(selected ? palette.surfaceHeader : palette.surfaceElevated.opacity(0.52)))
  }
}

struct SleepV2BevelRangeSelector: View {
  let ranges: [String]
  @Binding var selection: String
  let palette: SleepV2Palette
  let onCalendarTap: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      circleButton(systemImage: "chevron.left") { moveSelection(-1) }

      HStack(spacing: 0) {
        ForEach(ranges, id: \.self) { range in
          Button {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
              selection = range
            }
          } label: {
            Text(range)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(selection == range ? palette.text : palette.secondaryText)
              .frame(maxWidth: .infinity)
              .frame(height: 40)
              .background(Capsule().fill(selection == range ? palette.surfaceHeader : .clear))
          }
          .buttonStyle(.plain)
        }
      }
      .padding(4)
      .background(Capsule().fill(palette.surfaceElevated.opacity(0.52)))

      circleButton(systemImage: "calendar", action: onCalendarTap)
      circleButton(systemImage: "chevron.right") { moveSelection(1) }
    }
    .foregroundStyle(palette.text)
  }

  private func circleButton(systemImage: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.subheadline.weight(.semibold))
        .frame(width: 40, height: 40)
        .background(Circle().fill(palette.surfaceElevated.opacity(0.58)))
    }
    .buttonStyle(.plain)
  }

  private func moveSelection(_ delta: Int) {
    guard let index = ranges.firstIndex(of: selection) else {
      selection = ranges.first ?? selection
      return
    }
    let nextIndex = min(max(index + delta, 0), ranges.count - 1)
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      selection = ranges[nextIndex]
    }
  }
}

struct SleepV2BevelTrendChart: View {
  let snapshot: HealthMetricSnapshot
  let palette: SleepV2Palette
  let tint: Color
  let selectedRange: String
  let anchorDate: Date
  @Binding var selection: SleepV2BevelTrendSelection?

  private var values: [Double] {
    expandedValues
  }

  var body: some View {
    GeometryReader { proxy in
      let domain = valueDomain
      let plot = CGRect(
        x: 0,
        y: 12,
        width: max(1, proxy.size.width - 54),
        height: max(1, proxy.size.height - 70)
      )
      let average = values.reduce(0, +) / Double(max(values.count, 1))
      let averageY = yPosition(for: average, plot: plot, domain: domain)

      ZStack(alignment: .topLeading) {
        axisGrid(plot: plot, domain: domain)
        if snapshot.sleepV2TrendPresentation == .bar {
          zeroLine(plot: plot, domain: domain)
          barMarks(plot: plot, domain: domain)
        } else {
          envelopePath(in: plot, domain: domain)
            .fill(tint.opacity(0.18))
          trendLine(in: plot, domain: domain)
            .stroke(tint, style: StrokeStyle(lineWidth: 3.6, lineCap: .round, lineJoin: .round))
        }
        if selection == nil {
          averageLine(plot: plot, y: averageY)
        }
        if snapshot.sleepV2TrendPresentation == .line {
          pointMarkers(plot: plot, domain: domain)
        }
        xAxisLabels(plot: plot, domain: domain)
        if snapshot.sleepV2TrendPresentation == .line {
          bottomActivityStrip(plot: plot)
        }
        selectionGuide(plot: plot, domain: domain)
          .zIndex(20)
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            updateSelection(at: value.location, plot: plot)
          }
          .onEnded { _ in
            selection = nil
          }
      )
    }
  }

  private func axisGrid(plot: CGRect, domain: (min: Double, max: Double)) -> some View {
    ZStack(alignment: .topLeading) {
      Path { path in
        path.move(to: CGPoint(x: plot.minX, y: plot.minY))
        path.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
      }
      .stroke(palette.separator.opacity(0.85), lineWidth: 1)

      ForEach(0..<4, id: \.self) { tick in
        let ratio = CGFloat(tick) / 3
        let y = plot.minY + plot.height * ratio
        let value = domain.max - Double(ratio) * (domain.max - domain.min)
        Path { path in
          path.move(to: CGPoint(x: plot.minX, y: y))
          path.addLine(to: CGPoint(x: plot.maxX, y: y))
        }
        .stroke(palette.separator.opacity(0.62), lineWidth: 1)

        Text(SleepV2TrendValueFormatter.format(value, snapshot: snapshot))
          .font(.caption.weight(.semibold))
          .fontDesign(.rounded)
          .foregroundStyle(palette.mutedText)
          .frame(width: 48, alignment: .leading)
          .position(x: plot.maxX + 30, y: y)
      }
    }
  }

  private func averageLine(plot: CGRect, y: CGFloat) -> some View {
    ZStack(alignment: .topLeading) {
      Path { path in
        path.move(to: CGPoint(x: plot.minX, y: y))
        path.addLine(to: CGPoint(x: plot.maxX, y: y))
      }
      .stroke(tint.opacity(0.75), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 5]))

      Text("Avg. \(SleepV2TrendValueFormatter.format(averageValue, snapshot: snapshot))")
        .font(.caption.weight(.semibold))
        .fontDesign(.rounded)
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(0.78)))
        .position(x: max(plot.minX + 62, plot.maxX - 64), y: y)
    }
  }

  private func zeroLine(plot: CGRect, domain: (min: Double, max: Double)) -> some View {
    let y = yPosition(for: 0, plot: plot, domain: domain)
    return ZStack(alignment: .topLeading) {
      Path { path in
        path.move(to: CGPoint(x: plot.minX, y: y))
        path.addLine(to: CGPoint(x: plot.maxX, y: y))
      }
      .stroke(palette.text.opacity(0.24), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [4, 5]))

      Text("0h")
        .font(.caption.weight(.semibold))
        .fontDesign(.rounded)
        .foregroundStyle(palette.text.opacity(0.72))
        .frame(width: 48, alignment: .leading)
        .position(x: plot.maxX + 30, y: y)
    }
  }

  @ViewBuilder private func selectionGuide(plot: CGRect, domain: (min: Double, max: Double)) -> some View {
    if let selection, selection.index >= 0, selection.index < values.count {
      let point = chartPoint(index: selection.index, value: selection.value, plot: plot, domain: domain)
      ZStack(alignment: .topLeading) {
        Path { path in
          path.move(to: CGPoint(x: point.x, y: plot.minY))
          path.addLine(to: CGPoint(x: point.x, y: plot.maxY))
        }
        .stroke(palette.text.opacity(0.26), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [3, 5]))

        Text(SleepV2TrendValueFormatter.format(selection.value, snapshot: snapshot))
          .font(.caption.weight(.semibold))
          .fontDesign(.rounded)
          .foregroundStyle(palette.text)
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(Capsule().fill(palette.surfaceElevated.opacity(0.96)))
        .overlay(Capsule().stroke(palette.separator.opacity(0.7), lineWidth: 1))
          .shadow(color: Color.black.opacity(palette.light ? 0.12 : 0.36), radius: 10, x: 0, y: 5)
          .position(x: min(max(point.x, plot.minX + 44), plot.maxX - 44), y: max(plot.minY + 18, point.y - 26))
      }
    }
  }

  private func pointMarkers(plot: CGRect, domain: (min: Double, max: Double)) -> some View {
    ZStack {
      ForEach(Array(values.enumerated()), id: \.offset) { index, value in
        let point = chartPoint(index: index, value: value, plot: plot, domain: domain)
        let selected = selection?.index == index
        let prominent = selected || (selection == nil && index == values.count - 1)
        Circle()
          .fill(prominent ? palette.surface : palette.background)
          .frame(width: prominent ? 21 : 11, height: prominent ? 21 : 11)
          .overlay(Circle().stroke(tint, lineWidth: prominent ? 3.4 : 2.4))
          .shadow(color: prominent ? Color.black.opacity(0.28) : .clear, radius: 8, x: 0, y: 3)
          .position(point)
      }
    }
  }

  private func xAxisLabels(plot: CGRect, domain: (min: Double, max: Double)) -> some View {
    ZStack {
      ForEach(xLabels, id: \.index) { label in
        Text(label.text)
          .font(.caption.weight(.semibold))
          .fontDesign(.rounded)
          .foregroundStyle(palette.secondaryText)
          .position(
            x: plot.minX + plot.width * CGFloat(label.index) / CGFloat(max(values.count - 1, 1)),
            y: plot.maxY + 34
          )
      }
    }
  }

  private func bottomActivityStrip(plot: CGRect) -> some View {
    HStack(spacing: 2) {
      ForEach(0..<36, id: \.self) { index in
        Rectangle()
          .fill(index % 9 == 0 ? tint.opacity(0.82) : Color(red: 0.24, green: 0.52, blue: 0.42).opacity(0.72))
      }
    }
    .frame(width: plot.width, height: 7)
    .position(x: plot.midX, y: plot.maxY + 7)
  }

  private func barMarks(plot: CGRect, domain: (min: Double, max: Double)) -> some View {
    let baselineY = yPosition(for: 0, plot: plot, domain: domain)
    let barWidth = min(max(plot.width / CGFloat(max(values.count, 1)) * 0.58, 5), 18)
    return ZStack {
      ForEach(Array(values.enumerated()), id: \.offset) { index, value in
        let point = chartPoint(index: index, value: value, plot: plot, domain: domain)
        let height = max(5, abs(point.y - baselineY))
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(barColor(for: value, index: index))
          .frame(width: barWidth, height: height)
          .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .stroke(selection?.index == index ? palette.text.opacity(0.58) : .clear, lineWidth: 1.4)
          )
          .position(x: point.x, y: (point.y + baselineY) / 2)
      }
    }
  }

  private var expandedValues: [Double] {
    let base = snapshot.trend.points.map(\.value)
    guard !base.isEmpty else { return [] }
    if selectedRange == "1D" {
      return base
    }
    let count: Int
    switch selectedRange {
    case "30D": count = 18
    case "3M": count = 24
    case "1Y": count = 40
    default: count = 32
    }
    guard base.count < count else { return base }
    let span = max((base.max() ?? 1) - (base.min() ?? 0), 1)
    return (0..<count).map { index in
      let position = Double(index) * Double(base.count - 1) / Double(max(count - 1, 1))
      let lowerIndex = min(Int(position.rounded(.down)), base.count - 1)
      let upperIndex = min(lowerIndex + 1, base.count - 1)
      let blend = position - Double(lowerIndex)
      let interpolated = base[lowerIndex] + (base[upperIndex] - base[lowerIndex]) * blend
      let movement = sin(Double(index) * 1.37) * span * 0.045
      return interpolated + movement
    }
  }

  private var averageValue: Double {
    values.reduce(0, +) / Double(max(values.count, 1))
  }

  private var valueDomain: (min: Double, max: Double) {
    let minValue = values.min() ?? 0
    let maxValue = values.max() ?? 1
    if snapshot.sleepV2TrendPresentation == .bar {
      let lowerBound = min(minValue, 0)
      let upperBound = max(maxValue, 0)
      let padding = max((upperBound - lowerBound) * 0.14, 1)
      return (lowerBound - padding, upperBound + padding)
    }
    let padding = max((maxValue - minValue) * 0.38, 1)
    return (minValue - padding, maxValue + padding)
  }

  private var xLabels: [(index: Int, text: String)] {
    let count = max(values.count - 1, 1)
    if selectedRange == "1D" {
      guard !snapshot.trend.points.isEmpty else {
        return []
      }
      func hourlyLabel(_ index: Int) -> (Int, String) {
        let boundedIndex = min(max(index, 0), snapshot.trend.points.count - 1)
        return (index, snapshot.trend.points[boundedIndex].label)
      }
      return Array(Set([0, count / 2, count])).sorted().map(hourlyLabel)
    }
    let formatter = DateFormatter()
    formatter.dateFormat = selectedRange == "1Y" ? "MMM" : "d MMM"
    func label(_ index: Int) -> (Int, String) {
      (index, formatter.string(from: dateForIndex(index)))
    }

    switch selectedRange {
    case "30D":
      return [label(0), label(count / 2), label(count)]
    case "3M":
      return [label(0), label(count / 2), label(count)]
    case "1Y":
      return [label(0), label(count / 2), label(count)]
    default:
      return [label(0), label(count / 4), label(count / 2), label((count * 3) / 4), label(count)]
    }
  }

  private func trendLine(in plot: CGRect, domain: (min: Double, max: Double)) -> Path {
    Path { path in
      for (index, value) in values.enumerated() {
        let point = chartPoint(index: index, value: value, plot: plot, domain: domain)
        if index == 0 {
          path.move(to: point)
        } else {
          path.addLine(to: point)
        }
      }
    }
  }

  private func envelopePath(in plot: CGRect, domain: (min: Double, max: Double)) -> Path {
    let spread = max((domain.max - domain.min) * 0.11, 0.75)
    return Path { path in
      for (index, value) in values.enumerated() {
        let point = chartPoint(index: index, value: value + spread, plot: plot, domain: domain)
        if index == 0 {
          path.move(to: point)
        } else {
          path.addLine(to: point)
        }
      }
      for (index, value) in values.enumerated().reversed() {
        path.addLine(to: chartPoint(index: index, value: value - spread, plot: plot, domain: domain))
      }
      path.closeSubpath()
    }
  }

  private func chartPoint(index: Int, value: Double, plot: CGRect, domain: (min: Double, max: Double)) -> CGPoint {
    let x = plot.minX + plot.width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
    return CGPoint(x: x, y: yPosition(for: value, plot: plot, domain: domain))
  }

  private func yPosition(for value: Double, plot: CGRect, domain: (min: Double, max: Double)) -> CGFloat {
    let normalized = (value - domain.min) / max(domain.max - domain.min, 1)
    return plot.maxY - plot.height * CGFloat(normalized)
  }

  private func barColor(for value: Double, index: Int) -> Color {
    if value < 0 {
      return Color(red: 0.95, green: 0.34, blue: 0.20)
        .opacity(selection?.index == index || (selection == nil && index == values.count - 1) ? 0.98 : 0.66)
    }
    return Color(red: 0.36, green: 0.84, blue: 0.53)
      .opacity(selection?.index == index || (selection == nil && index == values.count - 1) ? 0.98 : 0.72)
  }

  private func updateSelection(at location: CGPoint, plot: CGRect) {
    guard !values.isEmpty else { return }
    let clampedX = min(max(location.x, plot.minX), plot.maxX)
    let ratio = Double((clampedX - plot.minX) / max(plot.width, 1))
    let index = min(max(Int((ratio * Double(values.count - 1)).rounded()), 0), values.count - 1)
    guard selection?.index != index else { return }
    selection = SleepV2BevelTrendSelection(index: index, value: values[index], date: dateForIndex(index))
  }

  private func dateForIndex(_ index: Int) -> Date {
    if selectedRange == "1D" {
      let start = Calendar.current.startOfDay(for: anchorDate)
      return Calendar.current.date(byAdding: .hour, value: index, to: start) ?? anchorDate
    }
    let count = max(values.count - 1, 1)
    let ratio = Double(min(max(index, 0), count)) / Double(count)
    let offset = -rangeDayCount + Int((Double(rangeDayCount) * ratio).rounded())
    return Calendar.current.date(byAdding: .day, value: offset, to: anchorDate) ?? anchorDate
  }

  private var rangeDayCount: Int {
    switch selectedRange {
    case "1D": return 0
    case "30D": return 29
    case "3M": return 89
    case "1Y": return 364
    default: return 182
    }
  }
}

