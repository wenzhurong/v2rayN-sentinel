import XCTest
@testable import SentinelCore

final class WatchDecisionTests: XCTestCase {
    func testFirstRunStartsAtEndWhenRequested() {
        let plan = WatchDecision.plan(previousFile: nil, previousOffset: 0,
                                      currentFile: "2026-07-02.txt", currentSize: 500,
                                      startAtEndIfNew: true)
        XCTAssertEqual(plan, ReadPlan(startOffset: 500, filename: "2026-07-02.txt"))
    }
    func testFirstRunStartsAtZeroWhenNotSkipping() {
        let plan = WatchDecision.plan(previousFile: nil, previousOffset: 0,
                                      currentFile: "2026-07-02.txt", currentSize: 500,
                                      startAtEndIfNew: false)
        XCTAssertEqual(plan.startOffset, 0)
    }
    func testDayRolloverReadsNewFileFromStart() {
        let plan = WatchDecision.plan(previousFile: "2026-07-02.txt", previousOffset: 500,
                                      currentFile: "2026-07-03.txt", currentSize: 20,
                                      startAtEndIfNew: true)
        XCTAssertEqual(plan, ReadPlan(startOffset: 0, filename: "2026-07-03.txt"))
    }
    func testTruncationResetsToZero() {
        let plan = WatchDecision.plan(previousFile: "2026-07-02.txt", previousOffset: 500,
                                      currentFile: "2026-07-02.txt", currentSize: 100,
                                      startAtEndIfNew: true)
        XCTAssertEqual(plan.startOffset, 0)
    }
    func testNormalAppendContinuesFromOffset() {
        let plan = WatchDecision.plan(previousFile: "2026-07-02.txt", previousOffset: 500,
                                      currentFile: "2026-07-02.txt", currentSize: 800,
                                      startAtEndIfNew: true)
        XCTAssertEqual(plan.startOffset, 500)
    }
}
