import Darwin
import Foundation
import SwiftUI
import UIKit

extension HealthDataStore {
  func trendRows(for route: HealthRoute) -> [HealthMetricSnapshot] {
    if previewMissingData {
      return []
    }
    switch route {
    case .sleep:
      return Self.sleepTrendRows
    case .recovery:
      return recoveryTrendRowsForV2()
    case .strain:
      return strainTrendRowsForV2()
    case .stress:
      return stressTrendRowsForV2()
    default:
      return []
    }
  }

  func recoveryTrendRowsForV2() -> [HealthMetricSnapshot] {
    guard !usesPreviewPacketData else {
      return []
    }

    return Self.recoveryTrendRows.compactMap { snapshot in
      switch snapshot.id {
      case "recovery-score-trend":
        guard let report = packetScoreReports["recovery"],
              let score = recoveryScoreValue(),
              let scoreText = Self.numberText(score, fractionDigits: 0) else {
          return nil
        }
        let trend = Self.dailyTrend(
          id: snapshot.trend.id,
          title: snapshot.trend.title,
          rows: Self.array(report["daily"]),
          valueKey: "score_0_to_100",
          unit: "%",
          fractionDigits: 0,
          resources: snapshot.trend.resources
        )
        guard trend.hasData else {
          return nil
        }
        return replacingHealthMonitorSnapshot(
          snapshot,
          value: scoreText,
          unit: "%",
          status: Self.recoveryQualityLabel(score: score),
          freshness: Self.latestDailyDateText(in: report) ?? "Latest",
          provenance: "metrics.recovery_score_from_features",
          source: .bridge("goose.recovery.v0"),
          trend: trend
        )
      case "recovery-hrv-trend":
        if let stored = dailyRecoveryMetricSnapshot(
          base: snapshot,
          valueKey: "hrv_rmssd_ms",
          unit: "ms",
          fractionDigits: 0,
          metricName: "HRV"
        ) {
          return stored
        }
        guard let report = packetInputReports["hrv"] else {
          return nil
        }
        guard Self.boolValue(report["pass"]) == true else {
          return nil
        }
        let trend = Self.dailyTrend(
          id: snapshot.trend.id,
          title: snapshot.trend.title,
          rows: Self.array(report["daily"]),
          valueKey: "rmssd_ms",
          unit: "ms",
          fractionDigits: 0,
          resources: snapshot.trend.resources
        )
        guard trend.hasData,
              let value = Self.doubleValue(Self.map(report, "score_result", "output")?["rmssd_ms"])
                ?? Self.array(report["daily"]).last.flatMap({ Self.doubleValue($0["rmssd_ms"]) }),
              let text = Self.numberText(value, fractionDigits: 0) else {
          return nil
        }
        return replacingHealthMonitorSnapshot(
          snapshot,
          value: text,
          unit: "ms",
          status: "Packet-derived",
          freshness: Self.latestDailyDateText(in: report) ?? "Latest",
          provenance: "metrics.hrv_features",
          source: .bridgeDeviceSensor("metrics.hrv_features"),
          trend: trend
        )
      case "recovery-rhr-trend":
        let dailyRecoveryRHRMetrics = dailyRecoveryMetricsWithRestingHR()
        if let metric = Self.preferredDailyRecoveryMetricWithRestingHR(from: dailyRecoveryRHRMetrics),
           let value = Self.doubleValue(metric["resting_hr_bpm"]),
           let text = Self.numberText(value, fractionDigits: 0) {
          return replacingHealthMonitorSnapshot(
            snapshot,
            value: text,
            unit: "bpm",
            status: dailyRecoveryRestingHRStatus(metric),
            freshness: metric["date_key"] as? String ?? "Latest",
            provenance: "daily_recovery_metrics | \(dailyRecoveryRestingHRProvenanceSummary(metric))",
            source: dailyRecoveryRestingHRSource(metric),
            trend: Self.restingHeartRateDailyRecoveryTrend(
              base: snapshot.trend,
              metrics: dailyRecoveryRHRMetrics
            )
          )
        }
        if let rollup = packetInputReports["resting_hr_rollup"],
           Self.boolValue(rollup["pass"]) == true,
           let value = Self.doubleValue(rollup["resting_hr_bpm"]),
           let text = Self.numberText(value, fractionDigits: 0) {
          return replacingHealthMonitorSnapshot(
            snapshot,
            value: text,
            unit: "bpm",
            status: "Packet-derived",
            freshness: Self.rollupFreshnessText(in: rollup) ?? "Today",
            provenance: "metrics.resting_hr_daily_rollup",
            source: .bridgeDeviceSensor("metrics.resting_hr_daily_rollup"),
            trend: Self.restingHeartRateRollupTrend(
              base: snapshot.trend,
              report: rollup
            )
          )
        }
        guard let report = packetInputReports["resting_hr"] else {
          return nil
        }
        let trend = Self.dailyTrend(
          id: snapshot.trend.id,
          title: snapshot.trend.title,
          rows: Self.array(report["daily"]),
          valueKey: "resting_hr_bpm",
          unit: "bpm",
          fractionDigits: 0,
          resources: snapshot.trend.resources
        )
        guard trend.hasData,
              let value = Self.doubleValue(Self.map(report, "resting")?["resting_hr_bpm"])
                ?? Self.array(report["daily"]).last.flatMap({ Self.doubleValue($0["resting_hr_bpm"]) }),
              let text = Self.numberText(value, fractionDigits: 0) else {
          return nil
        }
        return replacingHealthMonitorSnapshot(
          snapshot,
          value: text,
          unit: "bpm",
          status: "Packet-derived",
          freshness: Self.latestDailyDateText(in: report) ?? "Latest",
          provenance: "metrics.resting_hr_features",
          source: .bridgeDeviceSensor("metrics.resting_hr_features"),
          trend: trend
        )
      case "recovery-rr-trend":
        return dailyRecoveryMetricSnapshot(
          base: snapshot,
          valueKey: "respiratory_rate_rpm",
          unit: "rpm",
          fractionDigits: 1,
          metricName: "respiratory rate"
        )
      case "recovery-spo2-trend":
        return dailyRecoveryMetricSnapshot(
          base: snapshot,
          valueKey: "oxygen_saturation_percent",
          unit: "%",
          fractionDigits: 0,
          metricName: "oxygen saturation"
        )
      case "recovery-temp-trend":
        let imperial = TemperatureFormatting.preferredIsImperial
        let valueTransform: ((Double) -> Double)? = imperial
          ? { TemperatureFormatting.deltaValue(celsiusDelta: $0, imperial: true) }
          : nil
        return dailyRecoveryMetricSnapshot(
          base: snapshot,
          valueKey: "skin_temperature_delta_c",
          unit: TemperatureFormatting.unitSuffix(imperial: imperial),
          fractionDigits: 1,
          metricName: "skin temperature delta",
          signed: true,
          valueTransform: valueTransform
        )
      default:
        return nil
      }
    }
  }

  func dailyRecoveryMetricSnapshot(
    base snapshot: HealthMetricSnapshot,
    valueKey: String,
    unit: String,
    fractionDigits: Int,
    metricName: String,
    signed: Bool = false,
    valueTransform: ((Double) -> Double)? = nil
  ) -> HealthMetricSnapshot? {
    let metrics = dailyRecoveryMetricsWithValue(valueKey)
    var rows = Self.dailyRecoveryTrendRows(from: metrics, valueKey: valueKey)
    guard let metric = Self.preferredDailyRecoveryMetric(from: metrics, valueKey: valueKey) else {
      return nil
    }
    if let valueTransform {
      rows = rows.map { row in
        var transformed = row
        if let value = Self.doubleValue(row[valueKey]) {
          transformed[valueKey] = valueTransform(value)
        }
        return transformed
      }
    }
    let displayValue = Self.doubleValue(metric[valueKey]).map { valueTransform?($0) ?? $0 }
    let valueText = signed
      ? Self.signedNumberText(displayValue, fractionDigits: fractionDigits)
      : Self.numberText(displayValue, fractionDigits: fractionDigits)
    guard let valueText else {
      return nil
    }
    let trend = Self.dailyTrend(
      id: snapshot.trend.id,
      title: snapshot.trend.title,
      rows: rows,
      valueKey: valueKey,
      unit: unit,
      fractionDigits: fractionDigits,
      resources: snapshot.trend.resources
    )
    guard trend.hasData else {
      return nil
    }
    return replacingHealthMonitorSnapshot(
      snapshot,
      value: valueText,
      unit: unit,
      status: dailyRecoveryMetricStatus(metric),
      freshness: metric["date_key"] as? String ?? "Latest",
      provenance: "daily_recovery_metrics | \(dailyRecoveryMetricProvenanceSummary(metric))",
      source: dailyRecoveryMetricSource(metric, metricName: metricName),
      trend: trend
    )
  }

  func stressTrendRowsForV2() -> [HealthMetricSnapshot] {
    let summary = stressAlgorithmSummary()
    guard summary.hasData else {
      return []
    }

    return Self.stressTrendRows.compactMap { snapshot in
      switch snapshot.id {
      case "stress-score-trend":
        guard let score = summary.score,
              let text = Self.numberText(score, fractionDigits: 0) else {
          return nil
        }
        return replacingHealthMonitorSnapshot(
          snapshot,
          value: text,
          unit: "%",
          status: Self.stressTrendStatus(score: score),
          freshness: summary.freshness,
          provenance: summary.source.detail,
          source: summary.source,
          trend: Self.stressTrendModel(base: snapshot.trend, summary: summary)
        )
      case "non-activity-stress-trend":
        let wakingWindows = summary.windows.filter { !$0.isSleepWindow }
        guard !wakingWindows.isEmpty else {
          return nil
        }
        let average = wakingWindows.reduce(0.0) { $0 + $1.stress } / Double(wakingWindows.count)
        guard let text = Self.numberText(average, fractionDigits: 0) else {
          return nil
        }
        return replacingHealthMonitorSnapshot(
          snapshot,
          value: text,
          unit: "%",
          status: Self.stressTrendStatus(score: average),
          freshness: summary.freshness,
          provenance: "\(summary.source.detail) | sleep windows excluded",
          source: summary.source,
          trend: Self.stressTrendModel(base: snapshot.trend, summary: summary, points: wakingWindows, title: snapshot.title)
        )
      case "sleep-stress-trend":
        let sleepWindows = summary.windows.filter(\.isSleepWindow)
        guard !sleepWindows.isEmpty else {
          return nil
        }
        let average = sleepWindows.reduce(0.0) { $0 + $1.stress } / Double(sleepWindows.count)
        guard let text = Self.numberText(average, fractionDigits: 0) else {
          return nil
        }
        return replacingHealthMonitorSnapshot(
          snapshot,
          value: text,
          unit: "%",
          status: Self.stressTrendStatus(score: average),
          freshness: summary.freshness,
          provenance: "\(summary.source.detail) | likely sleep windows",
          source: summary.source,
          trend: Self.stressTrendModel(base: snapshot.trend, summary: summary, points: sleepWindows, title: snapshot.title)
        )
      default:
        return nil
      }
    }
  }

  func recoveryTrendOverviewRows() -> [HealthMetricSnapshot] {
    let bridgeRows = Dictionary(
      uniqueKeysWithValues: recoveryTrendRowsForV2().map { ($0.id, $0) }
    )
    return Self.recoveryTrendRows.map { bridgeRows[$0.id] ?? $0 }
  }
}
