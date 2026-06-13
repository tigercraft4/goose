import XCTest
@testable import GooseSwift

@MainActor
final class BaselineProgressTests: XCTestCase {
  func testBaselineProgressWithoutReadinessReportIsPending() {
    let store = HealthDataStore()

    let progress = store.baselineProgress()

    XCTAssertFalse(progress.hasReport)
    XCTAssertEqual(progress.readyFamilies, 0)
    XCTAssertEqual(progress.totalFamilies, 0)
    XCTAssertEqual(progress.fractionReady, 0)
    XCTAssertFalse(progress.allReady)
    XCTAssertTrue(progress.collectingFamilies.isEmpty)
  }

  func testBaselineProgressMapsReadinessReport() {
    let store = HealthDataStore()
    store.packetInputReports["readiness"] = [
      "ready_family_count": 1,
      "family_count": 3,
      "families": [
        [
          "metric_family": "hrv",
          "ready_input_count": 4,
          "required_input_count": 7,
          "score_ready": false,
        ],
        [
          "metric_family": "strain",
          "ready_input_count": 3,
          "required_input_count": 3,
          "score_ready": true,
        ],
        [
          "metric_family": "respiratory_rate",
          "ready_input_count": 0,
          "required_input_count": 2,
          "score_ready": false,
        ],
      ],
    ]

    let progress = store.baselineProgress()

    XCTAssertTrue(progress.hasReport)
    XCTAssertEqual(progress.readyFamilies, 1)
    XCTAssertEqual(progress.totalFamilies, 3)
    XCTAssertEqual(progress.fractionReady, 1.0 / 3.0, accuracy: 0.0001)
    XCTAssertFalse(progress.allReady)
    XCTAssertEqual(progress.collectingFamilies.map(\.id), ["hrv", "respiratory_rate"])
    XCTAssertEqual(progress.families.map(\.title), ["HRV", "Strain", "Respiratory Rate"])
    XCTAssertEqual(progress.families.map(\.readyInputs), [4, 3, 0])
    XCTAssertEqual(progress.families.map(\.requiredInputs), [7, 3, 2])
  }

  func testBaselineProgressFallsBackToFamilyCountsWhenReportCountsAreMissing() {
    let store = HealthDataStore()
    store.packetInputReports["readiness"] = [
      "families": [
        [
          "metric_family": "recovery",
          "ready_input_count": 4,
          "required_input_count": 4,
          "score_ready": true,
        ],
        [
          "metric_family": "sleep",
          "ready_input_count": 1,
          "required_input_count": 4,
          "score_ready": false,
        ],
      ],
    ]

    let progress = store.baselineProgress()

    XCTAssertEqual(progress.readyFamilies, 1)
    XCTAssertEqual(progress.totalFamilies, 2)
    XCTAssertFalse(progress.allReady)
  }

  func testAllReadyRequiresReportAndAtLeastOneFamily() {
    let noFamilies = BaselineProgressModel(
      hasReport: true,
      readyFamilies: 0,
      totalFamilies: 0,
      families: []
    )
    let allReady = BaselineProgressModel(
      hasReport: true,
      readyFamilies: 2,
      totalFamilies: 2,
      families: []
    )

    XCTAssertFalse(noFamilies.allReady)
    XCTAssertTrue(allReady.allReady)
  }
}
