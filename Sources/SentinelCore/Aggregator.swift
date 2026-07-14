import Foundation

public struct AggregatorParams: Sendable {
    public var burstWindow: TimeInterval
    public var burstThreshold: Int
    public var escalationCooldown: TimeInterval
    public var idleReset: TimeInterval
    public init(burstWindow: TimeInterval, burstThreshold: Int,
                escalationCooldown: TimeInterval, idleReset: TimeInterval) {
        self.burstWindow = burstWindow
        self.burstThreshold = burstThreshold
        self.escalationCooldown = escalationCooldown
        self.idleReset = idleReset
    }
}

public struct AggregateOutcome: Equatable, Sendable {
    public let key: String
    public let count: Int
    public let escalate: Bool
}

public final class Aggregator {
    private struct State {
        var count: Int
        var windowStart: Date
        var windowCount: Int
        var lastSeen: Date
        var escalatedUntil: Date?
    }

    private var states: [String: State] = [:]
    private let params: AggregatorParams

    public init(params: AggregatorParams) { self.params = params }

    public var trackedCount: Int { states.count }

    /// 聚合 key:优先 target|kind;抠不出则去掉 `[连接id 时长]` 前缀后的正文。
    public static func key(for record: LogRecord) -> String {
        let info = ConnectionErrorParser.extract(from: record.message)
        if let t = info.target { return "\(t)|\(info.kind)" }
        let stripped = record.message.replacingOccurrences(
            of: #"^\[\d+ [\d.]+s?\] "#, with: "", options: .regularExpression)
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func ingest(key: String, now: Date) -> AggregateOutcome {
        prune(now: now)
        var s = states[key] ?? State(count: 0, windowStart: now, windowCount: 0,
                                     lastSeen: now, escalatedUntil: nil)
        // 空闲过久 -> 视为新一波,清零计数与窗口(保留冷却时间)。
        if now.timeIntervalSince(s.lastSeen) > params.idleReset {
            s.count = 0
            s.windowStart = now
            s.windowCount = 0
        }
        s.count += 1
        s.lastSeen = now
        if now.timeIntervalSince(s.windowStart) > params.burstWindow {
            s.windowStart = now
            s.windowCount = 0
        }
        s.windowCount += 1
        var escalate = false
        if s.windowCount >= params.burstThreshold {
            if let until = s.escalatedUntil {
                if now >= until { escalate = true }
            } else {
                escalate = true
            }
            if escalate { s.escalatedUntil = now.addingTimeInterval(params.escalationCooldown) }
        }
        states[key] = s
        return AggregateOutcome(key: key, count: s.count, escalate: escalate)
    }

    private func prune(now: Date) {
        guard !states.isEmpty else { return }
        let retain = max(params.escalationCooldown, params.idleReset)
        states = states.filter { now.timeIntervalSince($0.value.lastSeen) <= retain }
    }
}
