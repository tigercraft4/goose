import Foundation
import SwiftUI

// MARK: - V24BiometricsResult

struct V24BiometricsResult {
  let spo2Percent: Double?       // nil when contact=false or no data
  let skinTempCelsius: Double?   // nil when contact=false or no data
  let respRateBpm: Double?       // nil when no data
  let sampleCount: Int
  let qualityFlag: String        // always "uncalibrated"
}

extension V24BiometricsResult {
  var spo2Text: String {
    guard let v = spo2Percent else { return "--" }
    return String(format: "%.1f%%", v)
  }

  func skinTempText(imperial: Bool) -> String {
    TemperatureFormatting.absoluteText(celsius: skinTempCelsius, imperial: imperial)
  }

  var respRateText: String {
    guard let v = respRateBpm else { return "--" }
    return String(format: "%.1f rpm", v)
  }

  var isEmpty: Bool {
    spo2Percent == nil && skinTempCelsius == nil && respRateBpm == nil
  }
}

// MARK: - HealthDataStore+V24Biometrics

extension HealthDataStore {
  // Fetches V24 biometric samples from the last overnight window (last 24h)
  // and derives SpO2 estimate, skin temperature, and resp rate.
  // Result is published on @MainActor.
  func runV24Biometrics() async {
    let db = databasePath
    let now = Date().timeIntervalSince1970
    let windowStart = now - 24 * 3600
    let deviceID = "goose.swift.v24.biometrics.v1"

    let asDouble: (Any?) -> Double? = { value in
      switch value {
      case let d as Double: return d
      case let f as Float: return Double(f)
      case let i as Int: return Double(i)
      case let n as NSNumber: return n.doubleValue
      default: return nil
      }
    }

    // Fetch V24 biometric window.
    let window: [String: Any]
    do {
      window = try await bridge.requestAsync(
        method: "biometrics.v24_between",
        args: [
          "database_path": db,
          "device_id": deviceID,
          "start_ts": windowStart,
          "end_ts": now,
        ]
      )
    } catch {
      v24BiometricsResult = nil
      return
    }

    // Extract SpO2 from the most recent contact=1 sample.
    let spo2Rows = window["spo2"] as? [[String: Any]] ?? []
    let contactSpo2 = spo2Rows.filter { row in
      (row["contact"] as? Int ?? 0) == 1 ||
      (row["contact"] as? NSNumber)?.intValue == 1
    }
    let latestSpo2 = contactSpo2.last
    var spo2Percent: Double? = nil

    if let latest = latestSpo2,
       let red = asDouble(latest["red"]).flatMap({ d -> UInt16? in
         guard d.isFinite, d >= 0 else { return nil }
         return UInt16(clamping: Int(d))
       }),
       let ir = asDouble(latest["ir"]).flatMap({ d -> UInt16? in
         guard d.isFinite, d >= 0 else { return nil }
         return UInt16(clamping: Int(d))
       }) {
      // Call spo2_from_raw to get the uncalibrated estimate.
      if let spo2Report = try? await bridge.requestAsync(
        method: "biometrics.spo2_from_raw",
        args: ["red": Int(red), "ir": Int(ir)]
      ) {
        spo2Percent = asDouble(spo2Report["spo2_pct"])
      }
    }

    // Extract skin temperature (most recent contact=1 sample, convert raw → Celsius).
    // raw value is stored as uint16; conversion: temp_c = raw / 100.0 (bridge plausibility gate uses this)
    let skinTempRows = window["skin_temp"] as? [[String: Any]] ?? []
    let contactSkinTemp = skinTempRows.filter { row in
      (row["contact"] as? Int ?? 0) == 1 ||
      (row["contact"] as? NSNumber)?.intValue == 1
    }
    let skinTempCelsius: Double? = contactSkinTemp.last.flatMap { row -> Double? in
      guard let raw = asDouble(row["raw"]), raw > 0 else { return nil }
      let celsius = raw / 100.0
      // Plausibility gate: 25–40 °C
      return (celsius >= 25 && celsius <= 40) ? celsius : nil
    }

    // Extract resp rate (average across all samples in window).
    // raw value is 100× the resp rate in rpm (e.g., raw=1500 → 15.0 rpm).
    let respRows = window["resp"] as? [[String: Any]] ?? []
    let respRawValues = respRows.compactMap { row -> Double? in
      guard let raw = asDouble(row["raw"]), raw > 0 else { return nil }
      return raw / 100.0
    }
    let respRateBpm: Double? = respRawValues.isEmpty ? nil
      : respRawValues.reduce(0, +) / Double(respRawValues.count)

    let sampleCount = spo2Rows.count + skinTempRows.count + respRows.count

    v24BiometricsResult = V24BiometricsResult(
      spo2Percent: spo2Percent,
      skinTempCelsius: skinTempCelsius,
      respRateBpm: respRateBpm,
      sampleCount: sampleCount,
      qualityFlag: "uncalibrated"
    )
  }
}
