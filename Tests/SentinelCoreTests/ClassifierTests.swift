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

    // 加固 #2:空/纯空白的噪音规则会匹配所有行,把全部重要错误静默降级。
    // 加固后应被忽略,重要错误仍升级。
    func testEmptyOrWhitespaceNoisePatternDoesNotSuppressImportant() {
        var rules = ClassifierRules.defaults
        rules.noisePatterns = [""]
        XCTAssertEqual(Classifier(rules: rules).classify(record(.error, "core crashed unexpectedly")),
                       .important)

        var rules2 = ClassifierRules.defaults
        rules2.noisePatterns = ["   "]
        XCTAssertEqual(Classifier(rules: rules2).classify(record(.fatal, "segfault in core")),
                       .important)
    }

    // 加固 #3:非法正则的重要关键词在 ICU 下静默返回 nil(不报错也不匹配),
    // 导致本应升级的错误被噪音规则降级。加固后应退回字面量匹配。
    func testInvalidImportantKeywordRegexFallsBackToLiteralMatch() {
        var rules = ClassifierRules.defaults
        rules.importantKeywords = ["[panic"]   // 未闭合字符类 → 非法正则
        let c = Classifier(rules: rules)
        let msg = "process (mihomo#1) returned a non-zero exit code (1) [panic]"
        XCTAssertEqual(c.classify(record(.error, msg)), .important)
    }
}
