import Foundation
import SwiftUI

// MARK: - RecoveryV1Result

struct RecoveryV1Result {
  let score: Int?
  let trustLevel: String
  let colourBand: String
  let zHRV: Double?
  let zRHR: Double?
}

extension RecoveryV1Result {
  var bandColor: Color {
    // CR-01 fix: Rust ColourBand::as_str() emits lowercase "verde"/"amarelo"/"vermelho".
    switch colourBand {
    case "verde": return .green
    case "amarelo": return .orange
    case "vermelho": return .red
    default: return .orange
    }
  }
}

// MARK: - HealthDataStore+Recovery

extension HealthDataStore {
  // Published via @Observable — stored property declared in the base class body
  // (extensions cannot add stored properties in Swift). The backing variable
  // `recoveryV1Result` is declared here as a computed shim that reads/writes the
  // stored backing ivar on the base class. However, since HealthDataStore uses
  // @Observable macro, we add the stored property to the class directly through
  // the extension's init trick is not possible — instead we use a workaround:
  // declare the state in the base class. This extension adds behaviour only.
  //
  // The @Published var recoveryV1Result: RecoveryV1Result? is declared in
  // HealthDataStore.swift (base class body) following the existing pattern for
  // properties like `sevenDayStrainCache`. The extension wires the logic.

  var recoveryV1IsCalibrating: Bool {
    recoveryV1Result?.trustLevel == "calibrating"
  }

  var recoveryV1TrustLabel: String? {
    switch recoveryV1Result?.trustLevel {
    case "calibrating": return String(localized: "Calibrating")
    case "provisional": return String(localized: "Provisional")
    default: return nil
    }
  }

  // Reads HRV and RHR from the existing recovery metric stores (same sources used
  // by recoveryHRVDisplayText / recoveryRestingHRDisplayText) and calls the bridge.
  func runRecoveryV1() async {
    let dateKey = Self.metricDateKey(for: Date())

    // Resolve numeric HRV (ms) — prefer stored daily recovery metric, fall back to packet report
    let hrvRmssdMs: Double? = {
      if let metric = preferredDailyRecoveryMetric(valueKey: "hrv_rmssd_ms", for: Date()),
         let v = Self.doubleValue(metric["hrv_rmssd_ms"]) {
        return v
      }
      if let report = packetInputReports["hrv"],
         Self.boolValue(report["pass"]) == true {
        let output = Self.map(report, "score_result", "output")
        if let v = Self.doubleValue(output?["rmssd_ms"]) { return v }
        if let v = Self.array(report["daily"]).last.flatMap({ Self.doubleValue($0["rmssd_ms"]) }) {
          return v
        }
      }
      return hkHRVSDNNMs
    }()

    // Resolve numeric RHR (bpm) — prefer stored daily recovery metric, fall back to packet report
    let restingHrBpm: Double? = {
      if let metric = preferredDailyRecoveryMetricWithRestingHR(),
         let v = Self.doubleValue(metric["resting_hr_bpm"]) {
        return v
      }
      if let rollup = packetInputReports["resting_hr_rollup"],
         Self.boolValue(rollup["pass"]) == true,
         let v = Self.doubleValue(rollup["resting_hr_bpm"]) {
        return v
      }
      return hkRestingHR
    }()

    guard let hrv = hrvRmssdMs, hrv > 0 else {
      self.recoveryV1Result = nil
      return
    }

    // CR-02 fix: do NOT substitute a synthetic RHR when none is available.
    // Rust handles absence via z_hrv-only fallback; a fabricated 55.0 biases z_rhr.
    let db = databasePath
    let deviceID = "goose.swift.recovery.v1"

    var bridgeArgs: [String: Any] = [
      "database_path": db,
      "device_id": deviceID,
      "date_key": dateKey,
      "hrv_rmssd_ms": hrv,
    ]
    if let rhr = restingHrBpm, rhr > 0 {
      bridgeArgs["resting_hr_bpm"] = rhr
    }

    do {
      let report = try await bridge.requestAsync(
        method: "metrics.goose_recovery_v1",
        args: bridgeArgs
      )
      let scoreRaw = Self.doubleValue(report["score_0_to_100"])
      let score = scoreRaw.map { Int($0.rounded()) }
      let trustLevel = report["trust_level"] as? String ?? "calibrating"
      let colourBand = report["colour_band"] as? String ?? "amarelo"
      let zHRV = Self.doubleValue(report["z_hrv"])
      let zRHR = Self.doubleValue(report["z_rhr"])
      self.recoveryV1Result = RecoveryV1Result(
        score: score,
        trustLevel: trustLevel,
        colourBand: colourBand,
        zHRV: zHRV,
        zRHR: zRHR
      )
    } catch {
      self.recoveryV1Result = nil
    }
  }
}
