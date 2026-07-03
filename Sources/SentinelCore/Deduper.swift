import Foundation

public final class Deduper {
    private var lastSeen: [String: Date] = [:]
    public let cooldown: TimeInterval

    public init(cooldown: TimeInterval) { self.cooldown = cooldown }

    /// 当前保留的签名数(诊断/测试用)。
    var trackedCount: Int { lastSeen.count }

    /// 归一化签名:抹掉 `#数字` 进程号,便于同类错误合并。
    public static func signature(of record: LogRecord) -> String {
        let stripped = record.message.replacingOccurrences(
            of: #"#\d+"#, with: "#N", options: .regularExpression)
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 同签名在冷却窗口内返回 false;否则记录并返回 true。
    public func shouldAlert(_ record: LogRecord, now: Date) -> Bool {
        pruneExpired(now: now)
        let sig = Deduper.signature(of: record)
        if let last = lastSeen[sig], now.timeIntervalSince(last) < cooldown {
            return false
        }
        lastSeen[sig] = now
        return true
    }

    /// 清理已过冷却窗口的签名。语义等价(过期项本就会放行并被覆盖),
    /// 但把 lastSeen 的规模上界压到"一个冷却窗口内出现的不同签名数"(加固 #6)。
    private func pruneExpired(now: Date) {
        guard !lastSeen.isEmpty else { return }
        lastSeen = lastSeen.filter { now.timeIntervalSince($0.value) < cooldown }
    }
}
