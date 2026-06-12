import Foundation
import SwiftUI

// MARK: - SleepStagingResult

struct SleepStagingResult {
  let stageMinutes: [String: Double]   // "wake" | "light" | "deep" | "rem" → minutes
  let sleepEfficiencyFraction: Double  // 0–1
  let solMinutes: Double               // sleep-onset latency
  let wasoMinutes: Double              // wake after sleep onset
  let tstMinutes: Double               // total sleep time
  let timeInBedMinutes: Double
  let stagingMethod: String            // "actigraphy_4class" | "no_imu"
  let respAvailable: Bool
}

extension SleepStagingResult {
  var sleepEfficiencyText: String {
    String(format: "%.0f%%", sleepEfficiencyFraction * 100)
  }

  var solText: String {
    HealthDataStore.minutesText(solMinutes)
  }

  var wasoText: String {
    HealthDataStore.minutesText(wasoMinutes)
  }

  var tstText: String {
    HealthDataStore.minutesText(tstMinutes)
  }

  // Sorted stage list for display (wake → light → deep → rem).
  var sortedStages: [(stage: String, minutes: Double)] {
    let order = ["wake", "light", "deep", "rem"]
    return order.compactMap { stage in
      guard let minutes = stageMinutes[stage], minutes > 0 else { return nil }
      return (stage: stage, minutes: minutes)
    }
  }

  var stagingMethodLabel: String {
    stagingMethod.contains("no_imu")
      ? String(localized: "no accelerometer")
      : String(localized: "4-class accelerometer")
  }
}

// MARK: - HealthDataStore+StagingSleep

extension HealthDataStore {
  // Calls metrics.sleep_staging using the primary sleep window from
  // packetScoreReports["sleep"]. Result is published on @MainActor.
  func runSleepStaging() async {
    let db = databasePath
    // Capture sleep report on @MainActor before the first await.
    let sleepReport = packetScoreReports["sleep"]
    let deviceID = "goose.swift.sleep.staging.v1"

    // Extract sleep window timestamps from the sleep score report.
    let asDouble: (Any?) -> Double? = { value in
      switch value {
      case let d as Double: return d
      case let f as Float: return Double(f)
      case let i as Int: return Double(i)
      case let n as NSNumber: return n.doubleValue
      default: return nil
      }
    }
    let asISO: (Any?) -> String? = { $0 as? String }

    // The sleep report exposes the window via sleep_window or sleep_v1_input.
    let window = sleepReport.flatMap { r in
      r["sleep_window"] as? [String: Any]
        ?? r["sleep_v1_input"] as? [String: Any]
        ?? r["sleep_input"] as? [String: Any]
    }
    let inputBlock = sleepReport.flatMap { r in
      r["sleep_v1_input"] as? [String: Any]
        ?? r["sleep_input"] as? [String: Any]
    }

    // Try ISO strings first, then unix_ms, then unix_s.
    let startTs: Double? = {
      if let iso = asISO(window?["start_time"] ?? inputBlock?["start_time"]) {
        return HealthDataStore.isoToUnixSeconds(iso)
      }
      if let ms = asDouble(window?["start_time_unix_ms"] ?? inputBlock?["start_time_unix_ms"]) {
        return ms / 1000.0
      }
      if let s = asDouble(window?["start_time_unix_s"] ?? inputBlock?["start_time_unix_s"]) {
        return s
      }
      return nil
    }()
    let endTs: Double? = {
      if let iso = asISO(window?["end_time"] ?? inputBlock?["end_time"]) {
        return HealthDataStore.isoToUnixSeconds(iso)
      }
      if let ms = asDouble(window?["end_time_unix_ms"] ?? inputBlock?["end_time_unix_ms"]) {
        return ms / 1000.0
      }
      if let s = asDouble(window?["end_time_unix_s"] ?? inputBlock?["end_time_unix_s"]) {
        return s
      }
      // Fallback: yesterday 10pm to today 8am.
      let now = Date().timeIntervalSince1970
      let end = now - (now.truncatingRemainder(dividingBy: 86400)) + 8 * 3600
      let start = end - 8 * 3600
      return start == end ? nil : start
    }()

    guard let sleepStart = startTs, let sleepEnd = endTs, sleepEnd > sleepStart else {
      sleepStagingResult = nil
      return
    }

    do {
      let report = try await bridge.requestAsync(
        method: "metrics.sleep_staging",
        args: [
          "database_path": db,
          "device_id": deviceID,
          "sleep_start_ts": sleepStart,
          "sleep_end_ts": sleepEnd,
        ]
      )
      let stageMinutesRaw = report["stage_minutes"] as? [String: Any] ?? [:]
      var stageMinutes: [String: Double] = [:]
      for (k, v) in stageMinutesRaw {
        stageMinutes[k] = asDouble(v) ?? 0
      }
      let result = SleepStagingResult(
        stageMinutes: stageMinutes,
        sleepEfficiencyFraction: asDouble(report["sleep_efficiency_fraction"]) ?? 0,
        solMinutes: asDouble(report["sol_minutes"]) ?? 0,
        wasoMinutes: asDouble(report["waso_minutes"]) ?? 0,
        tstMinutes: asDouble(report["tst_minutes"]) ?? 0,
        timeInBedMinutes: asDouble(report["time_in_bed_minutes"]) ?? 0,
        stagingMethod: report["staging_method"] as? String ?? "unknown",
        respAvailable: report["resp_available"] as? Bool ?? false
      )
      sleepStagingResult = result
    } catch {
      sleepStagingResult = nil
    }
  }

  // Parse an ISO-8601-ish UTC string (e.g. "2026-06-08T22:00:00.000Z") to Unix seconds.
  // Handles the subset of formats emitted by Rust bridge (no timezone conversion — assumed UTC).
  nonisolated static func isoToUnixSeconds(_ iso: String) -> Double? {
    let formats = [
      "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
      "yyyy-MM-dd'T'HH:mm:ssZ",
      "yyyy-MM-dd'T'HH:mm:ss",
      "yyyy-MM-dd HH:mm:ss",
    ]
    for fmt in formats {
      let df = DateFormatter()
      df.dateFormat = fmt
      df.locale = Locale(identifier: "en_US_POSIX")
      df.timeZone = TimeZone(identifier: "UTC")
      if let d = df.date(from: iso) {
        return d.timeIntervalSince1970
      }
    }
    return nil
  }
}
