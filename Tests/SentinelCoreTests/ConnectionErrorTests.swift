import XCTest
@testable import SentinelCore

final class ConnectionErrorTests: XCTestCase {
    func testExtractsDialTimeout() {
        let msg = "[1 5.0s] connection: open connection to 172.18.0.1:7881 using outbound/direct[direct]: dial tcp 172.18.0.1:7881: i/o timeout"
        let info = ConnectionErrorParser.extract(from: msg)
        XCTAssertEqual(info.target, "172.18.0.1:7881")
        XCTAssertEqual(info.kind, "i/o timeout")
    }
    func testExtractsRefused() {
        let info = ConnectionErrorParser.extract(from: "... dial tcp 10.0.0.1:443: connection refused")
        XCTAssertEqual(info.target, "10.0.0.1:443")
        XCTAssertEqual(info.kind, "connection refused")
    }
    func testFallbackWhenNoDial() {
        let info = ConnectionErrorParser.extract(from: "some other error")
        XCTAssertNil(info.target)
        XCTAssertEqual(info.kind, "some other error")
    }
}
