import XCTest
@testable import SentinelCore

final class ErrorHistoryTests: XCTestCase {
    private func entry(_ msg: String, sig: String) -> HistoryEntry {
        HistoryEntry(timestamp: "t", level: .error, message: msg,
                     signature: sig, classification: .important, count: 1)
    }

    func testNewestFirst() {
        let h = ErrorHistory(limit: 10)
        h.record(entry("a", sig: "a"))
        h.record(entry("b", sig: "b"))
        XCTAssertEqual(h.entries.map(\.message), ["b", "a"])
    }
    func testCapsAtLimit() {
        let h = ErrorHistory(limit: 2)
        h.record(entry("a", sig: "a"))
        h.record(entry("b", sig: "b"))
        h.record(entry("c", sig: "c"))
        XCTAssertEqual(h.entries.map(\.message), ["c", "b"])
    }
    func testConsecutiveSameSignatureBumpsCount() {
        let h = ErrorHistory(limit: 10)
        h.record(entry("boom", sig: "s"))
        h.record(entry("boom", sig: "s"))
        XCTAssertEqual(h.entries.count, 1)
        XCTAssertEqual(h.entries.first?.count, 2)
    }
    func testClearEmpties() {
        let h = ErrorHistory(limit: 10)
        h.record(entry("a", sig: "a"))
        h.clear()
        XCTAssertTrue(h.entries.isEmpty)
    }
}
