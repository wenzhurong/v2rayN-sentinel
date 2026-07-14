import Foundation

public final class LogParser {
    private struct Pending {
        let timestamp: String
        let level: LogLevel
        let firstMessage: String
        let firstRaw: String
        var extra: [String]
    }

    private let matcher: any HeaderMatcher
    private var pending: Pending?

    public init(matcher: any HeaderMatcher = SerilogHeaderMatcher()) {
        self.matcher = matcher
    }

    /// 向后兼容:v1 用的静态解析,固定 Serilog 格式。
    public static func parseHeader(_ line: String) -> (String, LogLevel, String)? {
        SerilogHeaderMatcher().match(line)
    }

    /// 喂入一行(不含结尾换行)。若此行开启新记录,返回上一条已完成的记录。
    public func consume(_ line: String) -> LogRecord? {
        if let (ts, level, msg) = matcher.match(line) {
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
