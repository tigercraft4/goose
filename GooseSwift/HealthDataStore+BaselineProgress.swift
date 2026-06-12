import Foundation

// MARK: - BaselineProgressModel

struct BaselineProgressModel {
  struct Family: Identifiable {
    let id: String
    let title: String
    let readyInputs: Int
    let requiredInputs: Int
    let ready: Bool
  }

  let hasReport: Bool
  let readyFamilies: Int
  let totalFamilies: Int
  let families: [Family]

  var allReady: Bool {
    hasReport && totalFamilies > 0 && readyFamilies >= totalFamilies
  }

  var fractionReady: Double {
    totalFamilies > 0 ? Double(readyFamilies) / Double(totalFamilies) : 0
  }

  var collectingFamilies: [Family] {
    families.filter { !$0.ready }
  }
}

// MARK: - HealthDataStore+BaselineProgress

extension HealthDataStore {
  // Surfaces the Rust metrics.input_readiness report as user-facing warm-up
  // progress: which score families have enough captured evidence to compute.
  // The raw next_actions on the report are engineering strings; the card
  // derives friendly copy from family names instead of forwarding them.
  func baselineProgress() -> BaselineProgressModel {
    guard let report = packetInputReports["readiness"] else {
      return BaselineProgressModel(hasReport: false, readyFamilies: 0, totalFamilies: 0, families: [])
    }
    let families = Self.array(report["families"]).map { row -> BaselineProgressModel.Family in
      let name = row["metric_family"] as? String ?? "metric"
      return BaselineProgressModel.Family(
        id: name,
        title: Self.baselineFamilyTitle(name),
        readyInputs: Self.intValue(row["ready_input_count"]) ?? 0,
        requiredInputs: Self.intValue(row["required_input_count"]) ?? 0,
        ready: row["score_ready"] as? Bool ?? false
      )
    }
    return BaselineProgressModel(
      hasReport: true,
      readyFamilies: Self.intValue(report["ready_family_count"]) ?? families.filter(\.ready).count,
      totalFamilies: Self.intValue(report["family_count"]) ?? families.count,
      families: families
    )
  }

  static func baselineFamilyTitle(_ rawValue: String) -> String {
    switch rawValue {
    case "hrv": return "HRV"
    case "sleep": return "Sleep"
    case "recovery": return "Recovery"
    case "strain": return "Strain"
    case "stress": return "Stress"
    case "readiness": return "Readiness"
    default: return rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
  }
}
