import Darwin
import Foundation
import SwiftUI
import UIKit

enum HealthMetricGroup: String, CaseIterable {
  case today = "Today"
  case vitals = "Vitals"
  case training = "Training"
  case algorithms = "Algorithms"
}

struct HealthTrendModel: Identifiable {
  let id: String
  let title: String
  let rangeLabel: String
  let summary: String
  let analysis: String
  let resources: [String]
  let points: [HealthTrendPoint]

  var hasData: Bool {
    !points.isEmpty
  }
}

struct HealthTrendPoint: Identifiable {
  let id = UUID()
  let label: String
  let value: Double
}

enum MetricSourceKind: String, Codable, CaseIterable, Equatable {
  case deviceCounter = "device_counter"
  case deviceSensor = "device_sensor"
  case localEstimate = "local_estimate"
  case unavailable
}

struct HealthDataSource: Equatable {
  enum Kind: String {
    case bridge = "Bridge"
    case local = "Local"
    case live = "Live"
    case unavailable = "Unavailable"
  }

  let kind: Kind
  let metricSourceKind: MetricSourceKind
  let detail: String

  init(kind: Kind, metricSourceKind: MetricSourceKind, detail: String) {
    self.kind = kind
    self.metricSourceKind = metricSourceKind
    self.detail = detail
  }

  static func bridge(_ detail: String) -> HealthDataSource {
    HealthDataSource(kind: .bridge, metricSourceKind: .localEstimate, detail: detail)
  }

  static func bridgeDeviceSensor(_ detail: String) -> HealthDataSource {
    HealthDataSource(kind: .bridge, metricSourceKind: .deviceSensor, detail: detail)
  }

  static func bridgeDeviceCounter(_ detail: String) -> HealthDataSource {
    HealthDataSource(kind: .bridge, metricSourceKind: .deviceCounter, detail: detail)
  }

  static func local(_ detail: String) -> HealthDataSource {
    HealthDataSource(kind: .local, metricSourceKind: .localEstimate, detail: detail)
  }

  static func live(_ detail: String) -> HealthDataSource {
    HealthDataSource(kind: .live, metricSourceKind: .deviceSensor, detail: detail)
  }

  static func unavailable(_ detail: String) -> HealthDataSource {
    HealthDataSource(kind: .unavailable, metricSourceKind: .unavailable, detail: detail)
  }

  static func deviceCounter(_ detail: String) -> HealthDataSource {
    HealthDataSource(kind: .live, metricSourceKind: .deviceCounter, detail: detail)
  }

  static func deviceSensor(_ detail: String) -> HealthDataSource {
    HealthDataSource(kind: .live, metricSourceKind: .deviceSensor, detail: detail)
  }

  static func localEstimate(_ detail: String) -> HealthDataSource {
    HealthDataSource(kind: .local, metricSourceKind: .localEstimate, detail: detail)
  }

  var label: String {
    "\(kind.rawValue): \(detail)"
  }
}

struct HealthSummaryRow: Identifiable {
  let id: String
  let label: String
  let value: String
  let status: String
  let source: HealthDataSource
  let systemImage: String

  init(
    _ label: String,
    value: String,
    status: String = "",
    source: HealthDataSource,
    systemImage: String = "circle"
  ) {
    self.id = label
    self.label = label
    self.value = value
    self.status = status
    self.source = source
    self.systemImage = systemImage
  }
}

struct HealthSleepStageSegment: Identifiable {
  let id: String
  let stage: String
  let startLabel: String
  let endLabel: String
  let durationMinutes: Double
  let confidence: Double?
  let source: HealthDataSource

  var displayStage: String {
    stage.capitalized
  }

  var durationText: String {
    HealthDataStore.minutesText(durationMinutes)
  }
}

struct PrimarySleepDetail: Identifiable {
  let id: String
  let dateLabel: String
  let startLabel: String
  let endLabel: String
  let durationText: String
  let durationMinutes: Double
  let timeInBedText: String
  let scoreText: String
  let qualityText: String
  let source: HealthDataSource
  let stages: [HealthSleepStageSegment]
  // ALG-SLP-01: HR-threshold sleep quality metrics
  let heartRateDipText: String
  let wasoText: String
  let solText: String
  let disturbanceText: String

  var scoreDisplayText: String {
    scoreText == "--" ? "--" : "\(scoreText)%"
  }
}

struct CardioLoadDay: Identifiable {
  let id: String
  let dateLabel: String
  let load: Double
  let status: String
  let durationText: String
  let percent: Double
  let source: HealthDataSource
}

struct CardioLoadAlgorithmSummary {
  let points: [CardioLoadDay]
  let status: String
  let freshness: String
  let source: HealthDataSource
  let sessionCount: Int
  let activityDayCount: Int
  let hasBaseline: Bool

  var latestPoint: CardioLoadDay? {
    points.last
  }

  var hasData: Bool {
    !points.isEmpty
  }
}

struct CardioLoadSessionContribution {
  let sessionID: String
  let start: Date
  let end: Date
  let dayStart: Date
  let load: Double
  let durationMinutes: Double
}

struct CardioLoadDailyComputation {
  let dayStart: Date
  let load: Double
  let durationMinutes: Double
  let status: String
}

struct EnergyStressPoint: Identifiable {
  let id: String
  let timeLabel: String
  let energy: Double
  let stress: Double
  let usage: Double
  let isSleepWindow: Bool
  let isChargeEvent: Bool
}

struct StressWindowPoint: Identifiable {
  let id: String
  let start: Date
  let end: Date
  let timeLabel: String
  let stress: Double
  let averageHeartRate: Double
  let sampleCount: Int
  let isSleepWindow: Bool

  var durationMinutes: Double {
    max(end.timeIntervalSince(start) / 60.0, 0)
  }
}

struct StressZoneSummary {
  let label: String
  let percent: Double
  let durationMinutes: Double
}

struct StressAlgorithmSummary {
  let score: Double?
  let status: String
  let averageHeartRate: Double?
  let averageHRV: Double?
  let windows: [StressWindowPoint]
  let high: StressZoneSummary
  let medium: StressZoneSummary
  let low: StressZoneSummary
  let sampleCount: Int
  let source: HealthDataSource
  let freshness: String
  let confidence: Double?
  let inputSummary: String

  var hasData: Bool {
    score != nil && !windows.isEmpty
  }
}

struct EnergyBankAlgorithmSummary {
  let percent: Double?
  let status: String
  let points: [EnergyStressPoint]
  let totalCharged: Double
  let totalDrained: Double
  let primarySleepCharge: Double
  let source: HealthDataSource
  let freshness: String
  let confidence: Double?
  let inputSummary: String

  var hasData: Bool {
    percent != nil && !points.isEmpty
  }
}

struct DailyMetricWindow {
  let dateKey: String
  let timezone: String
  let start: Date
  let end: Date
  let startISO: String
  let endISO: String
  let startTimeUnixMS: Int64
  let endTimeUnixMS: Int64
}

enum HealthPreviewState {
  case populated
  case missing
}

struct HealthAlgorithmDefinition: Identifiable {
  let id: String
  let displayName: String
  let family: String
  let status: String
  let provider: String
  let source: HealthDataSource

  init(row: [String: Any], source: HealthDataSource) {
    let algorithmID = row["algorithm_id"] as? String ?? row["id"] as? String ?? "unknown.algorithm"
    id = algorithmID
    displayName = row["display_name"] as? String ?? algorithmID
    family = row["metric_family"] as? String ?? "metric"
    status = row["status"] as? String ?? "ready"
    provider = row["provider"] as? String ?? row["implementation"] as? String ?? "goose"
    self.source = source
  }

  init(id: String, displayName: String, family: String, status: String, provider: String, source: HealthDataSource) {
    self.id = id
    self.displayName = displayName
    self.family = family
    self.status = status
    self.provider = provider
    self.source = source
  }
}
