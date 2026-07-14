import XCTest
@testable import SentinelCore

final class HeaderMatcherTests: XCTestCase {
    func testSerilogMatcherParsesGuiLine() {
        let m = SerilogHeaderMatcher()
        let r = m.match("2026-07-13 06:59:56.1234-ERROR boom")
        XCTAssertEqual(r?.0, "2026-07-13 06:59:56.1234")
        XCTAssertEqual(r?.1, .error)
        XCTAssertEqual(r?.2, "boom")
    }
    func testSerilogMatcherRejectsNonHeader() {
        XCTAssertNil(SerilogHeaderMatcher().match("    continuation"))
    }
    func testLogParserUsesInjectedMatcherByDefaultSerilog() {
        let p = LogParser()   // 默认 Serilog
        _ = p.consume("2026-07-13 09:00:00.0000-INFO started")
        let rec = p.consume("2026-07-13 09:00:01.0000-ERROR boom")
        XCTAssertEqual(rec?.level, .info)
        XCTAssertEqual(rec?.message, "started")
    }
}
