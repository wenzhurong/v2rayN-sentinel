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

    // 注:挂起记录在"连续 2 轮无活动"后才 flush(加固 #5 的宽限窗口),
    // 故各用例在写入后多调用一次 poll()。

    func testReadsErrorFromStartWhenNotSkipping() throws {
        try write("2026-07-02.txt",
            "2026-07-02 09:00:00.0000-INFO started\n2026-07-02 09:00:01.0000-ERROR boom\n")
        var got: [LogRecord] = []
        let w = LogWatcher(directory: dir, startAtEnd: false)
        w.onRecord = { got.append($0) }
        w.poll()   // 读取两行:INFO 完成,ERROR 挂起
        w.poll()   // 空闲 1
        w.poll()   // 空闲 2 → flush ERROR
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
        w.poll()   // 读到 fresh(挂起)
        w.poll()   // 空闲 1
        w.poll()   // 空闲 2 → flush fresh
        XCTAssertEqual(got.map(\.message), ["fresh"])
    }

    func testDayRolloverPicksNewFile() throws {
        try write("2026-07-02.txt", "2026-07-02 23:59:59.0000-INFO late\n")
        let w = LogWatcher(directory: dir, startAtEnd: true)
        var got: [LogRecord] = []
        w.onRecord = { got.append($0) }
        w.poll()
        try write("2026-07-03.txt", "2026-07-03 00:00:01.0000-ERROR newday\n")
        w.poll()   // 切到新文件,读到 newday(挂起)
        w.poll()   // 空闲 1
        w.poll()   // 空闲 2 → flush newday
        XCTAssertEqual(got.map(\.message), ["newday"])
    }

    // 加固 #4:换文件前未 flush,会丢掉上个文件的最后一条挂起记录。
    func testRolloverFlushesLastPendingRecordOfPreviousFile() throws {
        try write("2026-07-02.txt", "2026-07-02 23:59:59.0000-ERROR lastOfDay\n")
        var got: [LogRecord] = []
        let w = LogWatcher(directory: dir, startAtEnd: false)
        w.onRecord = { got.append($0) }
        w.poll()   // 读到 lastOfDay(挂起,尚未 flush)
        try write("2026-07-03.txt", "2026-07-03 00:00:01.0000-ERROR newday\n")
        w.poll()   // 换文件:应先 flush lastOfDay,再读 newday(挂起)
        w.poll()   // 空闲 1
        w.poll()   // 空闲 2 → flush newday
        XCTAssertEqual(got.map(\.message), ["lastOfDay", "newday"])
    }

    // 加固 #5:多行异常的续行若下一轮才到,不应因过早 flush 被丢弃。
    func testContinuationArrivingOnePollLaterStillMerges() throws {
        try write("2026-07-02.txt", "2026-07-02 09:00:00.0000-ERROR boom\n")
        var got: [LogRecord] = []
        let w = LogWatcher(directory: dir, startAtEnd: false)
        w.onRecord = { got.append($0) }
        w.poll()   // 读到 boom 行头(挂起)
        w.poll()   // 空闲 1(宽限未到,挂起保留)
        try append("2026-07-02.txt", "  at Foo.bar(x)\n")
        w.poll()   // 读到续行 → 并入挂起记录
        w.poll()   // 空闲 1
        w.poll()   // 空闲 2 → flush 合并后的记录
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(got.first?.level, .error)
        XCTAssertEqual(got.first?.message, "boom\n  at Foo.bar(x)")
    }
}
