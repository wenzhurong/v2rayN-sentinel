import XCTest
@testable import SentinelCore

final class SingboxHeaderMatcherTests: XCTestCase {
    private let m = SingboxHeaderMatcher()

    func testParsesConnectionError() {
        let line = "+0530 2026-07-06 19:31:37 ERROR [1456328237 5.0s] connection: open connection to 172.18.0.1:7881 using outbound/direct[direct]: dial tcp 172.18.0.1:7881: i/o timeout"
        let r = m.match(line)
        XCTAssertEqual(r?.0, "2026-07-06 19:31:37")
        XCTAssertEqual(r?.1, .error)
        XCTAssertEqual(r?.2, "[1456328237 5.0s] connection: open connection to 172.18.0.1:7881 using outbound/direct[direct]: dial tcp 172.18.0.1:7881: i/o timeout")
    }
    func testColonTimezoneAlsoAccepted() {
        let r = m.match("+05:30 2026-07-06 19:31:37 WARN something")
        XCTAssertEqual(r?.1, .warn)
        XCTAssertEqual(r?.2, "something")
    }
    func testPanicMapsToFatal() {
        XCTAssertEqual(m.match("+0000 2026-07-06 19:31:37 PANIC boom")?.1, .fatal)
    }
    func testNonHeaderReturnsNil() {
        XCTAssertNil(m.match("    at stack frame"))
    }
}
