import Foundation

// MARK: - Unit-aware temperature display formatting
//
// Sensor values and stored metrics are always Celsius; conversion to the
// profile unit preference happens only at display sites. Deltas scale by
// 9/5 without the 32° offset.

enum TemperatureFormatting {
  static func isImperial(unitSystemRaw: String) -> Bool {
    (MoreProfileUnitSystem(rawValue: unitSystemRaw) ?? .imperial) == .imperial
  }

  static var preferredIsImperial: Bool {
    isImperial(unitSystemRaw: UserDefaults.standard.string(forKey: OnboardingStorage.unitSystem) ?? "")
  }

  static func unitSuffix(imperial: Bool) -> String {
    imperial ? "°F" : "°C"
  }

  static func absoluteValue(celsius: Double, imperial: Bool) -> Double {
    imperial ? celsius * 9 / 5 + 32 : celsius
  }

  static func deltaValue(celsiusDelta: Double, imperial: Bool) -> Double {
    imperial ? celsiusDelta * 9 / 5 : celsiusDelta
  }

  static func absoluteText(celsius: Double?, imperial: Bool, fractionDigits: Int = 1) -> String {
    guard let celsius else { return "--" }
    let value = absoluteValue(celsius: celsius, imperial: imperial)
    return String(format: "%.\(fractionDigits)f %@", value, unitSuffix(imperial: imperial))
  }

  static func deltaText(celsiusDelta: Double, imperial: Bool, fractionDigits: Int = 2) -> String {
    let value = deltaValue(celsiusDelta: celsiusDelta, imperial: imperial)
    return String(format: "%+.\(fractionDigits)f %@", value, unitSuffix(imperial: imperial))
  }
}
