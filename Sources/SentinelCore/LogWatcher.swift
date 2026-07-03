import Foundation

public final class LogWatcher {
    public var onRecord: ((LogRecord) -> Void)?

    private let directory: URL
    private let startAtEnd: Bool
    private let fileManager: FileManager

    private var currentFile: String?
    private var offset: UInt64 = 0
    private var parser = LogParser()
    private var buffer = Data()   // 跨轮的残行

    public init(directory: URL, startAtEnd: Bool = true,
                fileManager: FileManager = .default) {
        self.directory = directory
        self.startAtEnd = startAtEnd
        self.fileManager = fileManager
    }

    /// 一次轮询周期。定时器每秒调用一次。
    public func poll() {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path),
              let newest = LogFileLocator.newestDateFile(in: names) else { return }
        let fileURL = directory.appendingPathComponent(newest)
        let attrs = (try? fileManager.attributesOfItem(atPath: fileURL.path)) ?? [:]
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0

        let plan = WatchDecision.plan(previousFile: currentFile, previousOffset: offset,
                                      currentFile: newest, currentSize: size,
                                      startAtEndIfNew: startAtEnd)

        if plan.filename != currentFile {
            currentFile = plan.filename
            parser = LogParser()
            buffer.removeAll()
        }

        var data = Data()
        if size > plan.startOffset, let fh = try? FileHandle(forReadingFrom: fileURL) {
            defer { try? fh.close() }
            try? fh.seek(toOffset: plan.startOffset)
            data = (try? fh.readToEnd()) ?? Data()
        }
        offset = size

        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            let line = String(decoding: lineData, as: UTF8.self)
            if let record = parser.consume(line) { onRecord?(record) }
        }

        // 流已空闲:输出挂起记录(如带续行的多行异常已到齐)。
        if data.isEmpty && buffer.isEmpty, let record = parser.flush() {
            onRecord?(record)
        }
    }
}
