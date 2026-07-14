import XCTest
@testable import AppLogic
import SentinelCore

@MainActor
final class AppModelTests: XCTestCase {
    final class SpyAlerter: Alerting {
        var presented: [(HistoryEntry, Bool)] = []
        var sounds: [String] = []
        func present(entry: HistoryEntry, important: Bool, autoDismiss: TimeInterval?) {
            presented.append((entry, important))
        }
        func playSound(named name: String) { sounds.append(name) }
        var aggregated: [(String, Int)] = []
        func presentAggregated(key: String, title: String, count: Int, autoDismiss: TimeInterval?) {
            aggregated.append((key, count))
        }
    }

    private func record(_ level: LogLevel, _ msg: String) -> LogRecord {
        LogRecord(timestamp: "2026-07-02 09:00:00.0000", level: level, message: msg, raw: msg)
    }

    private func makeModel(_ spy: SpyAlerter) -> AppModel {
        AppModel(settings: .default, alerter: spy)
    }

    func testInfoRecordDoesNothing() {
        let spy = SpyAlerter()
        let m = makeModel(spy)
        m.handle(record(.info, "started"), now: Date())
        XCTAssertTrue(spy.presented.isEmpty)
        XCTAssertTrue(m.history.isEmpty)
    }

    func testOrdinaryErrorShowsSmallToastNoSound() {
        let spy = SpyAlerter()
        let m = makeModel(spy)
        m.handle(record(.error, "process (mihomo#1) non-zero exit code (1)"), now: Date())
        XCTAssertEqual(spy.presented.count, 1)
        XCTAssertEqual(spy.presented.first?.1, false)   // important == false
        XCTAssertTrue(spy.sounds.isEmpty)
        XCTAssertEqual(m.history.count, 1)
    }

    func testImportantErrorShowsRedToastWithSound() {
        let spy = SpyAlerter()
        let m = makeModel(spy)
        m.handle(record(.error, "core crashed"), now: Date())
        XCTAssertEqual(spy.presented.first?.1, true)    // important == true
        XCTAssertEqual(spy.sounds, ["Basso"])
    }

    func testDuplicateWithinCooldownSuppressesAlertButCountsHistory() {
        let spy = SpyAlerter()
        let m = makeModel(spy)
        let t0 = Date(timeIntervalSince1970: 0)
        m.handle(record(.error, "core crashed"), now: t0)
        m.handle(record(.error, "core crashed"), now: t0.addingTimeInterval(10))
        XCTAssertEqual(spy.presented.count, 1)          // 第二次被冷却抑制
        XCTAssertEqual(m.history.first?.count, 2)       // 历史累加计数
    }

    func testPausedMonitoringIgnoresRecords() {
        let spy = SpyAlerter()
        let m = makeModel(spy)
        m.toggleMonitoring()                             // 暂停
        m.handle(record(.error, "core crashed"), now: Date())
        XCTAssertTrue(spy.presented.isEmpty)
        XCTAssertTrue(m.history.isEmpty)
    }

    // ===== v2:内核源路由 =====
    private func coreRec(_ msg: String) -> LogRecord {
        LogRecord(timestamp: "t", level: .error, message: msg, raw: msg)
    }

    func testCoreErrorGoesToAggregatedNotToast() {
        let spy = SpyAlerter(); let m = makeModel(spy)
        m.handle(coreRec("[1 5.0s] dial tcp 1.2.3.4:80: i/o timeout"), source: .singbox, now: Date())
        XCTAssertEqual(spy.aggregated.count, 1)
        XCTAssertEqual(spy.aggregated.first?.1, 1)      // count = 1
        XCTAssertTrue(spy.presented.isEmpty)            // 未升级 -> 无重要弹窗
    }
    func testCoreBurstEscalatesToImportantWithSound() {
        let spy = SpyAlerter()
        var s = Settings.default; s.burstThreshold = 3; s.burstWindowSeconds = 30
        let m = AppModel(settings: s, alerter: spy)
        let t0 = Date(timeIntervalSince1970: 0)
        for i in 0..<3 {
            m.handle(coreRec("[X 5.0s] dial tcp 1.2.3.4:80: i/o timeout"),
                     source: .singbox, now: t0.addingTimeInterval(Double(i)))
        }
        XCTAssertEqual(spy.presented.filter { $0.1 }.count, 1)  // 恰升级一次(important)
        XCTAssertEqual(spy.sounds, ["Basso"])
    }
    func testCoreMonitoringDisabledIgnoresCore() {
        let spy = SpyAlerter()
        var s = Settings.default; s.coreMonitoringEnabled = false
        let m = AppModel(settings: s, alerter: spy)
        m.handle(coreRec("dial tcp 1.2.3.4:80: i/o timeout"), source: .singbox, now: Date())
        XCTAssertTrue(spy.aggregated.isEmpty)
        XCTAssertTrue(spy.presented.isEmpty)
    }
    func testGuiPathUnchanged() {
        let spy = SpyAlerter(); let m = makeModel(spy)
        m.handle(record(.error, "core crashed"), now: Date())   // source 默认 .gui
        XCTAssertEqual(spy.presented.first?.1, true)
        XCTAssertEqual(spy.sounds, ["Basso"])
    }
}
