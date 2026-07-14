import XCTest
@testable import SentinelCore

final class XrayHeaderMatcherTests: XCTestCase {
    private let m = XrayHeaderMatcher()

    func testParsesWarning() {
        let r = m.match("2026/07/13 06:59:56.054278 [Warning] core: Xray 26.6.1 started")
        XCTAssertEqual(r?.0, "2026/07/13 06:59:56.054278")
        XCTAssertEqual(r?.1, .warn)
        XCTAssertEqual(r?.2, "core: Xray 26.6.1 started")
    }
    func testParsesErrorWithoutFraction() {
        let r = m.match("2026/07/13 07:00:00 [Error] failed to dial")
        XCTAssertEqual(r?.1, .error)
        XCTAssertEqual(r?.2, "failed to dial")
    }
    func testNonHeaderReturnsNil() {
        XCTAssertNil(m.match("  > some continuation"))
    }
}
