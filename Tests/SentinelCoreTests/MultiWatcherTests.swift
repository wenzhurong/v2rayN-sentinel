import XCTest
@testable import SentinelCore

final class MultiWatcherTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("mw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }
    private func write(_ n: String, _ t: String) throws {
        try t.data(using: .utf8)!.write(to: dir.appendingPathComponent(n))
    }

    func testRoutesRecordsToTheirSource() throws {
        try write("2026-07-13.txt", "2026-07-13 09:00:00.0000-ERROR gui boom\n")
        try write("sbox_2026-07-13.txt", "+0530 2026-07-13 09:00:00 ERROR [1 5.0s] dial tcp 1.2.3.4:80: i/o timeout\n")
        var got: [(SourceKind, String)] = []
        let mw = MultiWatcher(directory: dir, sources: [.gui, .singbox], startAtEnd: false)
        mw.onRecord = { rec, kind in got.append((kind, rec.message)) }
        mw.poll(); mw.poll(); mw.poll()
        XCTAssertTrue(got.contains { $0.0 == .gui && $0.1 == "gui boom" })
        XCTAssertTrue(got.contains { $0.0 == .singbox && $0.1.contains("i/o timeout") })
    }
    func testMissingSourceFileIsSilent() throws {
        // 只有 gui 文件,singbox 源没有对应文件 -> 不报错、不产出 singbox 记录
        try write("2026-07-13.txt", "2026-07-13 09:00:00.0000-INFO hi\n")
        var kinds: [SourceKind] = []
        let mw = MultiWatcher(directory: dir, sources: [.gui, .singbox], startAtEnd: false)
        mw.onRecord = { _, k in kinds.append(k) }
        mw.poll(); mw.poll()
        XCTAssertFalse(kinds.contains(.singbox))
    }
}
