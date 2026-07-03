import XCTest
@testable import SentinelCore

final class LogParserTests: XCTestCase {
    func testParseHeaderExtractsFields() {
        let line = "2026-06-25 10:51:33.7293-ERROR CliWrap failed exit code (1)."
        let parsed = LogParser.parseHeader(line)
        XCTAssertEqual(parsed?.0, "2026-06-25 10:51:33.7293")
        XCTAssertEqual(parsed?.1, .error)
        XCTAssertEqual(parsed?.2, "CliWrap failed exit code (1).")
    }

    func testContinuationLineReturnsNilHeader() {
        XCTAssertNil(LogParser.parseHeader("    Standard error:"))
    }

    func testConsumeEmitsPreviousRecordOnNewHeader() {
        let p = LogParser()
        XCTAssertNil(p.consume("2026-07-02 09:00:00.0000-INFO started"))
        let rec = p.consume("2026-07-02 09:00:01.0000-ERROR boom")
        XCTAssertEqual(rec?.level, .info)
        XCTAssertEqual(rec?.message, "started")
    }

    func testMultiLineRecordJoinsContinuations() {
        let p = LogParser()
        _ = p.consume("2026-07-02 09:00:01.0000-ERROR boom")
        XCTAssertNil(p.consume("Standard error:"))
        XCTAssertNil(p.consume("stack line 2"))
        let rec = p.flush()
        XCTAssertEqual(rec?.level, .error)
        XCTAssertEqual(rec?.message, "boom\nStandard error:\nstack line 2")
        XCTAssertEqual(rec?.raw,
            "2026-07-02 09:00:01.0000-ERROR boom\nStandard error:\nstack line 2")
    }

    func testFlushOnEmptyReturnsNil() {
        XCTAssertNil(LogParser().flush())
    }
}
