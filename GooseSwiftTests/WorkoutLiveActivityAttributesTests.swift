import XCTest
@testable import GooseSwift

final class WorkoutLiveActivityAttributesTests: XCTestCase {
  func testDecodesPreUnitPreferenceAttributesWithMetricDefault() throws {
    let data = Data("""
    {
      "sessionID": "legacy-session",
      "activityName": "Run",
      "activitySystemImage": "figure.run",
      "activityTintHex": "#00ff88",
      "environmentName": "Outdoor",
      "usesGPS": true
    }
    """.utf8)

    let attributes = try JSONDecoder().decode(WorkoutLiveActivityAttributes.self, from: data)

    XCTAssertEqual(attributes.sessionID, "legacy-session")
    XCTAssertTrue(attributes.usesGPS)
    XCTAssertFalse(attributes.usesImperialUnits)
  }

  func testRoundTripsUnitPreferenceAttribute() throws {
    let attributes = WorkoutLiveActivityAttributes(
      sessionID: "session",
      activityName: "Ride",
      activitySystemImage: "bicycle",
      activityTintHex: "#ffcc00",
      environmentName: "Outdoor",
      usesGPS: true,
      usesImperialUnits: true
    )

    let encoded = try JSONEncoder().encode(attributes)
    let decoded = try JSONDecoder().decode(WorkoutLiveActivityAttributes.self, from: encoded)

    XCTAssertEqual(decoded.sessionID, attributes.sessionID)
    XCTAssertTrue(decoded.usesGPS)
    XCTAssertTrue(decoded.usesImperialUnits)
  }
}
