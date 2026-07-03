import XCTest
@testable import SentinelCore

final class ClassifierTests: XCTestCase {
    private func record(_ level: LogLevel, _ msg: String) -> LogRecord {
        LogRecord(timestamp: "2026-07-02 09:00:00.0000", level: level, message: msg, raw: msg)
    }

    func testInfoIsIgnored() {
        let c = Classifier(rules: .defaults)
        XCTAssertEqual(c.classify(record(.info, "started")), .ignored)
    }
    func testMihomoNoiseIsOrdinary() {
        let c = Classifier(rules: .defaults)
        let msg = "CliWrap...process (mihomo#2615) returned a non-zero exit code (1)."
        XCTAssertEqual(c.classify(record(.error, msg)), .ordinary)
    }
    func testBash127NoiseIsOrdinary() {
        let c = Classifier(rules: .defaults)
        let msg = "process (bash#1550) returned a non-zero exit code (127)."
        XCTAssertEqual(c.classify(record(.error, msg)), .ordinary)
    }
    func testUnknownErrorIsImportant() {
        let c = Classifier(rules: .defaults)
        XCTAssertEqual(c.classify(record(.error, "core crashed unexpectedly")), .important)
    }
    func testImportantKeywordOverridesNoise() {
        var rules = ClassifierRules.defaults
        rules.importantKeywords = ["panic"]
        let c = Classifier(rules: rules)
        let msg = "process (mihomo#1) non-zero exit code panic"
        XCTAssertEqual(c.classify(record(.error, msg)), .important)
    }
}
