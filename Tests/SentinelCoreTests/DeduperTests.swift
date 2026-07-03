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

    // 加固 #6:过期签名应被清理,避免长跑进程 lastSeen 无界增长。
    func testExpiredSignaturesArePruned() {
        let d = Deduper(cooldown: 60)
        _ = d.shouldAlert(rec("a"), now: Date(timeIntervalSince1970: 0))
        _ = d.shouldAlert(rec("b"), now: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(d.trackedCount, 2)
        // a、b 均已过期(>60s)后再来一条 c,过期项应被清理,只剩 c。
        _ = d.shouldAlert(rec("c"), now: Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(d.trackedCount, 1)
    }
}
