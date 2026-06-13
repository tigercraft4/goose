import XCTest
@testable import GooseSwift

final class WorkoutLiveActivityAttributesTests: XCTestCase {
  func testDecodesPreUnitPreferenceStateWithMetricDefault() throws {
    let data = Data("""
    {
      "status": "Running",
      "elapsedSeconds": 120,
      "activeCalories": 15,
      "isPaused": false,
      "updatedAt": 0
    }
    """.utf8)

    let state = try JSONDecoder().decode(WorkoutLiveActivityAttributes.ContentState.self, from: data)

    XCTAssertEqual(state.status, "Running")
    XCTAssertEqual(state.elapsedSeconds, 120)
    XCTAssertFalse(state.usesImperialUnits)
  }

  func testRoundTripsUnitPreferenceState() throws {
    let state = WorkoutLiveActivityAttributes.ContentState(
      status: "Riding",
      timerStartDate: nil,
      elapsedSeconds: 300,
      currentHeartRate: 142,
      averageHeartRate: 138,
      maxHeartRate: 156,
      activeCalories: 38,
      distanceMeters: 1200,
      isPaused: false,
      updatedAt: Date(timeIntervalSince1970: 0),
      usesImperialUnits: true
    )

    let encoded = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(WorkoutLiveActivityAttributes.ContentState.self, from: encoded)

    XCTAssertEqual(decoded.status, state.status)
    XCTAssertEqual(decoded.currentHeartRate, state.currentHeartRate)
    XCTAssertTrue(decoded.usesImperialUnits)
  }
}
