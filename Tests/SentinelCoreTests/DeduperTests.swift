import XCTest
@testable import SentinelCore

final class DeduperTests: XCTestCase {
    private func rec(_ msg: String) -> LogRecord {
        LogRecord(timestamp: "t", level: .error, message: msg, raw: msg)
    }

    func testSignatureStripsProcessIds() {
        let a = Deduper.signature(of: rec("process (mihomo#2615) failed"))
        let b = Deduper.signature(of: rec("process (mihomo#1199) failed"))
        XCTAssertEqual(a, b)
    }
    func testFirstAlertPasses() {
        let d = Deduper(cooldown: 60)
        XCTAssertTrue(d.shouldAlert(rec("boom"), now: Date(timeIntervalSince1970: 0)))
    }
    func testWithinCooldownSuppressed() {
        let d = Deduper(cooldown: 60)
        _ = d.shouldAlert(rec("boom"), now: Date(timeIntervalSince1970: 0))
        XCTAssertFalse(d.shouldAlert(rec("boom"), now: Date(timeIntervalSince1970: 30)))
    }
    func testAfterCooldownPassesAgain() {
        let d = Deduper(cooldown: 60)
        _ = d.shouldAlert(rec("boom"), now: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(d.shouldAlert(rec("boom"), now: Date(timeIntervalSince1970: 61)))
    }
    func testDifferentSignaturesIndependent() {
        let d = Deduper(cooldown: 60)
        _ = d.shouldAlert(rec("boom"), now: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(d.shouldAlert(rec("other"), now: Date(timeIntervalSince1970: 1)))
    }
}
