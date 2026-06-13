import XCTest
@testable import GooseSwift

final class HistoricalRangeParsingTests: XCTestCase {
  func testRangePageStateReportsExplicitEmptyRange() {
    let payload = commandResponsePayload(pageCurrent: 42, pageOldest: 42, pageEnd: 128)

    let state = GooseBLEClient.historicalRangePageState(fromCommandResponsePayload: payload)

    XCTAssertEqual(state?.pageCurrent, 42)
    XCTAssertEqual(state?.pageOldest, 42)
    XCTAssertEqual(state?.pageEnd, 128)
    XCTAssertEqual(state?.pagesBehind, 0)
  }

  func testRangePageStateHandlesWrappedPageWindow() {
    let payload = commandResponsePayload(pageCurrent: 3, pageOldest: 98, pageEnd: 100)

    let state = GooseBLEClient.historicalRangePageState(fromCommandResponsePayload: payload)

    XCTAssertEqual(state?.pagesBehind, 5)
  }

  func testRangePageStateReturnsNilForShortBody() {
    let payload: [UInt8] = [0xaa, 0x00, 34, 57, 1, 1, 2, 3]

    XCTAssertNil(GooseBLEClient.historicalRangePageState(fromCommandResponsePayload: payload))
  }

  private func commandResponsePayload(
    pageCurrent: UInt32,
    pageOldest: UInt32,
    pageEnd: UInt32
  ) -> [UInt8] {
    var body = [UInt8](repeating: 0, count: 25)
    body[0] = 1
    writeUInt32LE(0, to: &body, at: 1)
    writeUInt32LE(0, to: &body, at: 5)
    writeUInt32LE(pageCurrent, to: &body, at: 9)
    writeUInt32LE(pageOldest, to: &body, at: 13)
    writeUInt32LE(0, to: &body, at: 17)
    writeUInt32LE(pageEnd, to: &body, at: 21)
    return [0xaa, 0x00, 34, 57, 1] + body
  }

  private func writeUInt32LE(_ value: UInt32, to bytes: inout [UInt8], at offset: Int) {
    bytes[offset] = UInt8(value & 0xff)
    bytes[offset + 1] = UInt8((value >> 8) & 0xff)
    bytes[offset + 2] = UInt8((value >> 16) & 0xff)
    bytes[offset + 3] = UInt8((value >> 24) & 0xff)
  }
}
