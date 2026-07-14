import Foundation

public final class LogWatcher {
    public var onRecord: ((LogRecord) -> Void)?

    private let directory: URL
    private let startAtEnd: Bool
    private let fileManager: FileManager
    private let filePattern: String
    private let headerMatcher: any HeaderMatcher

    private var currentFile: String?
    private var offset: UInt64 = 0
    private var parser: LogParser
    private var buffer = Data()   // 跨轮的残行
    private var idlePolls = 0     // 连续无活动的轮询数

    /// 连续多少轮无任何活动后,才 flush 挂起记录(给多行续行留出到达窗口)。
    private static let idleFlushThreshold = 2

    public init(directory: URL, startAtEnd: Bool = true,
                fileManager: FileManager = .default,
                filePattern: String = #"[0-9]{4}-[0-9]{2}-[0-9]{2}\.txt"#,
                headerMatcher: any HeaderMatcher = SerilogHeaderMatcher()) {
        self.directory = directory
        self.startAtEnd = startAtEnd
        self.fileManager = fileManager
        self.filePattern = filePattern
        self.headerMatcher = headerMatcher
        self.parser = LogParser(matcher: headerMatcher)
    }

    /// 一次轮询周期。定时器每秒调用一次。
    public func poll() {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path),
              let newest = LogFileLocator.newestMatchingFile(in: names, pattern: filePattern) else { return }
        let fileURL = directory.appendingPathComponent(newest)
        let attrs = (try? fileManager.attributesOfItem(atPath: fileURL.path)) ?? [:]
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0

        let plan = WatchDecision.plan(previousFile: currentFile, previousOffset: offset,
                                      currentFile: newest, currentSize: size,
                                      startAtEndIfNew: startAtEnd)

        if plan.filename != currentFile {
            // 换文件(首轮或跨天)前,先把上个文件的挂起记录输出,避免丢末条(加固 #4)。
            if let record = parser.flush() { onRecord?(record) }
            currentFile = plan.filename
            parser = LogParser(matcher: headerMatcher)
            buffer.removeAll()
            idlePolls = 0
        }

        var data = Data()
        if size > plan.startOffset, let fh = try? FileHandle(forReadingFrom: fileURL) {
            defer { try? fh.close() }
            try? fh.seek(toOffset: plan.startOffset)
            data = (try? fh.readToEnd()) ?? Data()
        }
        offset = size

        buffer.append(data)
        var consumedLine = false
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            let line = String(decoding: lineData, as: UTF8.self)
            consumedLine = true
            if let record = parser.consume(line) { onRecord?(record) }
        }

        // 本轮有任何活动(读到字节/消费了整行/仍有残行)→ 重置空闲计数,
        // 给挂起记录的续行留出到达窗口;仅在连续空闲达到阈值后才 flush(加固 #5)。
        if !data.isEmpty || consumedLine || !buffer.isEmpty {
            idlePolls = 0
        } else {
            idlePolls += 1
            if idlePolls >= LogWatcher.idleFlushThreshold, let record = parser.flush() {
                onRecord?(record)
                idlePolls = 0
            }
        }
    }
}
