import XCTest
@testable import SentinelCore

final class SmokeTests: XCTestCase {
    func testVersionExists() {
        XCTAssertEqual(SentinelCore.version, "0.1.0")
    }
}
