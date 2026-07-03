import Foundation

public final class Deduper {
    private var lastSeen: [String: Date] = [:]
    public let cooldown: TimeInterval

    public init(cooldown: TimeInterval) { self.cooldown = cooldown }

    /// 归一化签名:抹掉 `#数字` 进程号,便于同类错误合并。
    public static func signature(of record: LogRecord) -> String {
        let stripped = record.message.replacingOccurrences(
            of: #"#\d+"#, with: "#N", options: .regularExpression)
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 同签名在冷却窗口内返回 false;否则记录并返回 true。
    public func shouldAlert(_ record: LogRecord, now: Date) -> Bool {
        let sig = Deduper.signature(of: record)
        if let last = lastSeen[sig], now.timeIntervalSince(last) < cooldown {
            return false
        }
        lastSeen[sig] = now
        return true
    }
}
