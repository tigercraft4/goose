import XCTest
@testable import GooseSwift

final class TemperatureFormattingTests: XCTestCase {
  override func tearDown() {
    UserDefaults.standard.removeObject(forKey: OnboardingStorage.unitSystem)
    super.tearDown()
  }

  func testAbsoluteTemperatureUsesOffsetOnlyForImperial() {
    XCTAssertEqual(
      TemperatureFormatting.absoluteValue(celsius: 37, imperial: true),
      98.6,
      accuracy: 0.0001
    )
    XCTAssertEqual(
      TemperatureFormatting.absoluteValue(celsius: 37, imperial: false),
      37,
      accuracy: 0.0001
    )
  }

  func testTemperatureDeltaScalesWithoutFahrenheitOffset() {
    XCTAssertEqual(
      TemperatureFormatting.deltaValue(celsiusDelta: 1, imperial: true),
      1.8,
      accuracy: 0.0001
    )
    XCTAssertEqual(
      TemperatureFormatting.deltaValue(celsiusDelta: -0.5, imperial: false),
      -0.5,
      accuracy: 0.0001
    )
  }

  func testAbsoluteTextFormatsNilAndUnits() {
    XCTAssertEqual(TemperatureFormatting.absoluteText(celsius: nil, imperial: true), "--")
    XCTAssertEqual(TemperatureFormatting.absoluteText(celsius: 37, imperial: true), "98.6 °F")
    XCTAssertEqual(TemperatureFormatting.absoluteText(celsius: 37, imperial: false), "37.0 °C")
  }

  func testDeltaTextKeepsSignAndUnit() {
    XCTAssertEqual(TemperatureFormatting.deltaText(celsiusDelta: 1, imperial: true), "+1.80 °F")
    XCTAssertEqual(TemperatureFormatting.deltaText(celsiusDelta: -0.5, imperial: false), "-0.50 °C")
  }

  func testPreferredUnitDefaultsImperialAndHonorsStoredMetricPreference() {
    UserDefaults.standard.removeObject(forKey: OnboardingStorage.unitSystem)
    XCTAssertTrue(TemperatureFormatting.preferredIsImperial)

    UserDefaults.standard.set(MoreProfileUnitSystem.metric.rawValue, forKey: OnboardingStorage.unitSystem)
    XCTAssertFalse(TemperatureFormatting.preferredIsImperial)
  }
}
