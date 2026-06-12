import Foundation
import SwiftUI

// MARK: - ReadinessResult

struct ReadinessResult {
  let level: String          // "rundown" | "strained" | "balanced" | "primed" | "unknown"
  let acwrZone: String       // "under_training" | "optimal" | "caution" | "danger" | "unknown"
  let acwr: Double?
  let monotony: Double?
  let monotonyHigh: Bool
  let insufficientData: Bool
}

extension ReadinessResult {
  var levelLabel: String {
    switch level {
    case "rundown":  return String(localized: "Run-down")
    case "strained": return String(localized: "Strained")
    case "balanced": return String(localized: "Balanced")
    case "primed":   return String(localized: "Primed")
    default:         return String(localized: "Insufficient data")
    }
  }

  var levelIcon: String {
    switch level {
    case "rundown":  return "exclamationmark.triangle.fill"
    case "strained": return "bolt.fill"
    case "balanced": return "checkmark.circle.fill"
    case "primed":   return "flame.fill"
    default:         return "questionmark.circle"
    }
  }

  var levelColor: Color {
    switch level {
    case "rundown":  return .red
    case "strained": return .orange
    case "balanced": return Color(red: 0.24, green: 0.68, blue: 0.44)
    case "primed":   return Color(red: 0.22, green: 0.54, blue: 0.92)
    default:         return .secondary
    }
  }

  var acwrZoneLabel: String {
    switch acwrZone {
    case "under_training": return String(localized: "Under-training")
    case "optimal":        return String(localized: "Optimal")
    case "caution":        return String(localized: "Caution")
    case "danger":         return String(localized: "Danger")
    default:               return String(localized: "Unknown")
    }
  }
}

// MARK: - HealthDataStore+Readiness

extension HealthDataStore {
  // Fetches the last 28 days of exercise sessions, aggregates daily strain,
  // and calls metrics.goose_readiness_v1. Result is published on @MainActor.
  func runReadinessV1() async {
    let db = databasePath
    let now = Date()
    // Capture the live today strain on @MainActor before the first await.
    let liveStrainReport = packetScoreReports["strain"]

    // Resolve daily strain pairs for the last 28 days from exercise_sessions.
    // Each day's strain = sum of session strains capped at 21.
    let windowStart = now.addingTimeInterval(-28 * 24 * 3600).timeIntervalSince1970
    let windowEnd = now.timeIntervalSince1970

    // Local pure helpers.
    let asArray: (Any?) -> [[String: Any]] = { value in
      (value as? [[String: Any]]) ?? []
    }
    let asDouble: (Any?) -> Double? = { value in
      switch value {
      case let d as Double: return d
      case let f as Float: return Double(f)
      case let i as Int: return Double(i)
      case let n as NSNumber: return n.doubleValue
      default: return nil
      }
    }
    let nestedMap: (Any?, String, String) -> [String: Any]? = { value, k1, k2 in
      guard let outer = value as? [String: Any],
            let inner = outer[k1] as? [String: Any] else { return nil }
      return inner[k2] as? [String: Any]
    }

    let sessionsResult: [[String: Any]]
    do {
      let deviceID = "goose.swift.readiness.v1"
      let report = try await bridge.requestAsync(
        method: "exercise.sessions_between",
        args: [
          "database_path": db,
          "device_id": deviceID,
          "ts_start": windowStart,
          "ts_end": windowEnd,
        ]
      )
      sessionsResult = asArray(report["sessions"])
    } catch {
      sessionsResult = []
    }

    // Aggregate sessions per calendar-day (UTC). Each day gets one strain value.
    var dailyStrainByDay: [String: Double] = [:]
    let cal = Calendar(identifier: .gregorian)
    for session in sessionsResult {
      guard let tsStart = asDouble(session["start_ts"]) else { continue }
      let date = Date(timeIntervalSince1970: tsStart)
      let key = "\(cal.component(.year, from: date))-\(cal.component(.month, from: date))-\(cal.component(.day, from: date))"
      let strain = asDouble(session["strain"]) ?? 0
      dailyStrainByDay[key, default: 0] += strain
    }

    // Also include today's live strain from packetScoreReports if available.
    let todayKey: String = {
      let d = Date()
      return "\(cal.component(.year, from: d))-\(cal.component(.month, from: d))-\(cal.component(.day, from: d))"
    }()
    let liveStrainToday = asDouble(nestedMap(liveStrainReport, "score_result", "output")?["score_0_to_21"])
    if let live = liveStrainToday, live > 0 {
      // Use live value; override any session-aggregated value for today.
      dailyStrainByDay[todayKey] = live
    }

    // Build chronological pairs (timestamp_s, strain) over the 28-day window.
    // Pair timestamp = noon UTC on that day (arbitrary; algorithm uses position not timestamp).
    var dailyStrain: [[Double]] = []
    for daysBack in stride(from: 27, through: 0, by: -1) {
      guard let day = cal.date(byAdding: .day, value: -daysBack, to: now) else { continue }
      let key = "\(cal.component(.year, from: day))-\(cal.component(.month, from: day))-\(cal.component(.day, from: day))"
      let ts = day.timeIntervalSince1970
      let strainValue = min(dailyStrainByDay[key] ?? 0, 21.0)
      dailyStrain.append([ts, strainValue])
    }

    // Call metrics.goose_readiness_v1.
    do {
      let report = try await bridge.requestAsync(
        method: "metrics.goose_readiness_v1",
        args: [
          "daily_strain": dailyStrain,
        ]
      )
      let level = report["level"] as? String ?? "unknown"
      let acwrZone = report["acwr_zone"] as? String ?? "unknown"
      let acwr = asDouble(report["acwr"])
      let monotony = asDouble(report["monotony"])
      let monotonyHigh = report["monotony_high"] as? Bool ?? false
      let insufficientData = report["insufficient_data"] as? Bool ?? true
      readinessResult = ReadinessResult(
        level: level,
        acwrZone: acwrZone,
        acwr: acwr,
        monotony: monotony,
        monotonyHigh: monotonyHigh,
        insufficientData: insufficientData
      )
    } catch {
      readinessResult = ReadinessResult(
        level: "unknown",
        acwrZone: "unknown",
        acwr: nil,
        monotony: nil,
        monotonyHigh: false,
        insufficientData: true
      )
    }
  }
}
