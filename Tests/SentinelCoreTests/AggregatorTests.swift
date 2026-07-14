import XCTest
@testable import SentinelCore

final class AggregatorTests: XCTestCase {
    private func rec(_ msg: String) -> LogRecord {
        LogRecord(timestamp: "t", level: .error, message: msg, raw: msg)
    }
    private func agg() -> Aggregator {
        Aggregator(params: AggregatorParams(burstWindow: 30, burstThreshold: 3,
                                            escalationCooldown: 300, idleReset: 10))
    }
    private func t(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

    func testKeyGroupsByTargetAndKind() {
        let a = Aggregator.key(for: rec("[1 5.0s] dial tcp 1.2.3.4:80: i/o timeout"))
        let b = Aggregator.key(for: rec("[999 5.0s] dial tcp 1.2.3.4:80: i/o timeout"))
        XCTAssertEqual(a, b)   // 连接id 不同但目标+类型相同 -> 同 key
    }
    func testCountAccumulatesAndEscalatesAtThreshold() {
        let a = agg()
        XCTAssertFalse(a.ingest(key: "k", now: t(0)).escalate)   // 1
        XCTAssertFalse(a.ingest(key: "k", now: t(1)).escalate)   // 2
        let third = a.ingest(key: "k", now: t(2))               // 3 -> 阈值
        XCTAssertTrue(third.escalate)
        XCTAssertEqual(third.count, 3)
    }
    func testCooldownPreventsReEscalation() {
        let a = agg()
        _ = a.ingest(key: "k", now: t(0)); _ = a.ingest(key: "k", now: t(1))
        XCTAssertTrue(a.ingest(key: "k", now: t(2)).escalate)    // 升级
        XCTAssertFalse(a.ingest(key: "k", now: t(3)).escalate)   // 冷却中
    }
    func testIdleResetsCount() {
        let a = agg()
        _ = a.ingest(key: "k", now: t(0))
        let after = a.ingest(key: "k", now: t(100))              // 距上次 100s > idleReset(10)
        XCTAssertEqual(after.count, 1)                          // 计数重置
    }
    func testExpiredKeysPruned() {
        let a = agg()
        _ = a.ingest(key: "a", now: t(0))
        _ = a.ingest(key: "b", now: t(1000))                    // a 早已过期
        XCTAssertEqual(a.trackedCount, 1)
    }
}
