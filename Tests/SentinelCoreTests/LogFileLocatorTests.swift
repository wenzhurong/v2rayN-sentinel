import XCTest
@testable import SentinelCore

final class LogFileLocatorTests: XCTestCase {
    func testPicksNewestDate() {
        let names = ["2026-06-30.txt", "2026-07-02.txt", "2026-07-01.txt"]
        XCTAssertEqual(LogFileLocator.newestDateFile(in: names), "2026-07-02.txt")
    }
    func testIgnoresNonDateFiles() {
        let names = ["cache.db", "README.md", "2026-07-02.txt", "notes.txt"]
        XCTAssertEqual(LogFileLocator.newestDateFile(in: names), "2026-07-02.txt")
    }
    func testReturnsNilWhenNoDateFiles() {
        XCTAssertNil(LogFileLocator.newestDateFile(in: ["cache.db", "x.txt"]))
    }
}
