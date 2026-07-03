import XCTest
@testable import SentinelCore

final class LogLevelTests: XCTestCase {
    func testParseKnownLevels() {
        XCTAssertEqual(LogLevel(rawValue: "ERROR"), .error)
        XCTAssertEqual(LogLevel(rawValue: "INFO"), .info)
    }
    func testIsErrorTrueForErrorAndFatal() {
        XCTAssertTrue(LogLevel.error.isError)
        XCTAssertTrue(LogLevel.fatal.isError)
    }
    func testIsErrorFalseForInfoDebugWarn() {
        XCTAssertFalse(LogLevel.info.isError)
        XCTAssertFalse(LogLevel.debug.isError)
        XCTAssertFalse(LogLevel.warn.isError)
    }
}
