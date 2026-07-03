import Foundation

public final class LogParser {
    private struct Pending {
        let timestamp: String
        let level: LogLevel
        let firstMessage: String
        let firstRaw: String
        var extra: [String]
    }

    private var pending: Pending?

    public init() {}

    private static let headerRegex = try! NSRegularExpression(
        pattern: #"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+)-([A-Za-z]+) ?(.*)$"#
    )

    /// 若该行是记录行头,返回 (时间戳, 级别, 正文);否则返回 nil(续行)。
    public static func parseHeader(_ line: String) -> (String, LogLevel, String)? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let m = headerRegex.firstMatch(in: line, options: [], range: range) else {
            return nil
        }
        func group(_ i: Int) -> String {
            guard let r = Range(m.range(at: i), in: line) else { return "" }
            return String(line[r])
        }
        let ts = group(1)
        let level = LogLevel(rawValue: group(2).uppercased()) ?? .unknown
        return (ts, level, group(3))
    }

    /// 喂入一行(不含结尾换行)。若此行开启新记录,返回上一条已完成的记录。
    public func consume(_ line: String) -> LogRecord? {
        if let (ts, level, msg) = LogParser.parseHeader(line) {
            let completed = flush()
            pending = Pending(timestamp: ts, level: level,
                              firstMessage: msg, firstRaw: line, extra: [])
            return completed
        } else {
            pending?.extra.append(line)
            return nil
        }
    }

    /// 输出挂起的记录(流空闲时调用)。
    public func flush() -> LogRecord? {
        guard let p = pending else { return nil }
        pending = nil
        let message = ([p.firstMessage] + p.extra).joined(separator: "\n")
        let raw = ([p.firstRaw] + p.extra).joined(separator: "\n")
        return LogRecord(timestamp: p.timestamp, level: p.level,
                         message: message, raw: raw)
    }
}
