import XCTest
@testable import SentinelCore

final class LogWatcherTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("watcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }
    private func write(_ name: String, _ text: String) throws {
        try text.data(using: .utf8)!.write(to: dir.appendingPathComponent(name))
    }
    private func append(_ name: String, _ text: String) throws {
        let url = dir.appendingPathComponent(name)
        let fh = try FileHandle(forWritingTo: url)
        defer { try? fh.close() }
        try fh.seekToEnd()
        try fh.write(contentsOf: text.data(using: .utf8)!)
    }

    func testReadsErrorFromStartWhenNotSkipping() throws {
        try write("2026-07-02.txt",
            "2026-07-02 09:00:00.0000-INFO started\n2026-07-02 09:00:01.0000-ERROR boom\n")
        var got: [LogRecord] = []
        let w = LogWatcher(directory: dir, startAtEnd: false)
        w.onRecord = { got.append($0) }
        w.poll()   // 读取两行:INFO 完成,ERROR 挂起
        w.poll()   // 无新数据 → flush ERROR
        XCTAssertEqual(got.map(\.level), [.info, .error])
        XCTAssertEqual(got.last?.message, "boom")
    }

    func testSkipsHistoryWhenStartAtEnd() throws {
        try write("2026-07-02.txt", "2026-07-02 09:00:00.0000-ERROR old\n")
        var got: [LogRecord] = []
        let w = LogWatcher(directory: dir, startAtEnd: true)
        w.onRecord = { got.append($0) }
        w.poll()   // 从末尾起,忽略旧行
        try append("2026-07-02.txt", "2026-07-02 09:01:00.0000-ERROR fresh\n")
        w.poll()
        w.poll()
        XCTAssertEqual(got.map(\.message), ["fresh"])
    }

    func testDayRolloverPicksNewFile() throws {
        try write("2026-07-02.txt", "2026-07-02 23:59:59.0000-INFO late\n")
        let w = LogWatcher(directory: dir, startAtEnd: true)
        var got: [LogRecord] = []
        w.onRecord = { got.append($0) }
        w.poll()
        try write("2026-07-03.txt", "2026-07-03 00:00:01.0000-ERROR newday\n")
        w.poll()
        w.poll()
        XCTAssertEqual(got.map(\.message), ["newday"])
    }
}
